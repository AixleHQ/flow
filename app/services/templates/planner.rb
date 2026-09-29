# frozen_string_literal: true

module Templates
  # Works out what installing a catalog template would do, without doing it:
  # which project, which resources are created, reused or in conflict, what
  # happens to the board, and what the checklist will ask for afterwards.
  #
  # Pure — no writes. The install page renders it, `install_template` returns it
  # while conflicts are unresolved, and Templates::Installer re-runs it inside
  # its transaction and refuses when the result differs from what the user
  # confirmed (design §7.4).
  class Planner
    Error = Class.new(StandardError)
    NotAllowed = Class.new(Error)
    NotInstallable = Class.new(Error)
    StaleTemplate = Class.new(Error)
    InvalidInputs = Class.new(Error)

    # action: create | reuse | conflict (unresolved) | copy (resolved: install as a copy)
    Item = Struct.new(:section, :key, :name, :action, :existing_id, :install_name, keyword_init: true) do
      def ref = "#{section}.#{key}"
      def to_h = super.compact
    end

    Plan = Struct.new(:catalog_template, :package, :target_kind, :company, :project, :project_name, :inputs,
                      :items, :board_action, :column_map, :warnings, :checklist, :platform_tools,
                      :internal_servers, keyword_init: true) do
      def conflicts = items.select { |item| item.action == "conflict" }
      def resolved? = conflicts.empty?
      def item(section, key) = items.find { |i| i.section == section && i.key == key }

      # What the user confirmed: which package, where, and every create / reuse /
      # copy decision. Input values and the new project's name are left out —
      # they are typed on the same page, and inputs only matter here through the
      # decisions they change, which are in.
      def digest
        decisions = [ catalog_template.package_digest, target_kind, project&.id,
                      items.map(&:to_h), board_action, column_map.sort ]
        Digest::SHA256.hexdigest(decisions.to_json)
      end
    end

    RESOLUTIONS = %w[use_existing copy].freeze
    # Sections whose rows are matched by name in an existing project.
    MATCHED_SECTIONS = %w[agents skills mcp_servers tools assets].freeze

    # @param target [Hash] { company:, project_name: } for a new project, or { project: }
    # @param expected [Hash] { version:, commit_sha: } the page the user saw; nil skips the check
    # @param resolutions [Hash{String => String}] "agents.architect" => "use_existing" | "copy",
    #   and "columns.<key>" => a board column id of the target project
    # @param provided_secrets [Array<String>] names of the secrets the user is supplying now
    def initialize(catalog_template:, user:, target:, inputs: {}, resolutions: {}, expected: nil, provided_secrets: [])
      @catalog_template = catalog_template
      @user = user
      @target = target.to_h.symbolize_keys
      @raw_inputs = inputs.to_h.stringify_keys
      @resolutions = resolutions.to_h.stringify_keys
      @expected = expected&.to_h&.symbolize_keys
      @provided_secrets = Array(provided_secrets).map(&:to_s)
    end

    # A registry skill is named by its slug, as SkillsRegistryService names it;
    # an authored one by its frontmatter.
    def self.skill_name(package, entry)
      return entry["registry"].to_s.split("@").last if entry["registry"]

      Skills::SkillMarkdown.name(package.file(entry["path"]).to_s.dup.force_encoding(Encoding::UTF_8)) || entry["key"]
    end

    def call
      check_installable!
      package = Validator.validate!(@catalog_template.to_package)
      project, company, target_kind = resolve_target!(package)

      plan = Plan.new(
        catalog_template: @catalog_template, package: package, target_kind: target_kind,
        company: company, project: project, project_name: new_project_name(company),
        inputs: resolve_inputs!(package), items: [], warnings: [], checklist: [], column_map: {},
        platform_tools: resolve_platform_tools!(package), internal_servers: resolve_internal_servers!(package)
      )
      plan_resources(plan)
      plan_board(plan)
      plan_checklist(plan)
      plan
    rescue Validator::InvalidPackage => e
      raise NotInstallable, "This template is not valid on this installation: #{e.message}"
    end

    private

    # ---- target and preconditions ----------------------------------------

    def check_installable!
      raise NotInstallable, "This template has been withdrawn: #{@catalog_template.revocation_reason}" if @catalog_template.revoked?
      raise NotInstallable, "This template needs a newer version of Flow" unless @catalog_template.installable?
      return unless @expected

      stale = @expected[:version].present? && @expected[:version].to_i != @catalog_template.version
      stale ||= @expected[:commit_sha].present? && @expected[:commit_sha] != @catalog_template.commit_sha
      raise StaleTemplate, "This template changed since you opened it — review the new version first" if stale
    end

    def resolve_target!(package)
      if (project = @target[:project])
        raise NotAllowed, "A whole-project template always installs as a new project" if package.kind == "project"
        raise NotAllowed, "You cannot add resources to this project" unless policy(project: project).install_into_project?

        [ project, project.company, "existing_project" ]
      else
        company = @target[:company] or raise Error, "Choose a company or a project to install into"
        raise NotAllowed, "You cannot create projects in this company" unless policy(company: company).create?

        [ nil, company, "new_project" ]
      end
    end

    def policy(project: nil, company: nil)
      context = project ? ProjectContext.new(@user, {}, project: project) : BaseContext.new(@user, {}, company: company)
      Web::Company::TemplateInstallsPolicy.new(context, nil)
    end

    def new_project_name(company)
      return nil if @target[:project]

      base = @target[:project_name].presence || @catalog_template.name
      taken = company.projects.where("name = ? OR name LIKE ?", base, "#{Project.sanitize_sql_like(base)} (%)").pluck(:name)
      return base if taken.exclude?(base)

      suffix = 2
      suffix += 1 while taken.include?("#{base} (#{suffix})")
      "#{base} (#{suffix})"
    end

    def resolve_inputs!(package)
      package.inputs.to_h do |input|
        key = input["key"]
        value = @raw_inputs.key?(key) ? @raw_inputs[key] : input["default"]
        value = ActiveModel::Type::Boolean.new.cast(value).to_s if input["type"] == "boolean"
        value = value.to_s
        raise InvalidInputs, "#{input['label']} is required" if value.blank? && input["required"]
        if input["type"] == "select" && value.present? && Array(input["options"]).exclude?(value)
          raise InvalidInputs, "#{input['label']} must be one of: #{input['options'].join(', ')}"
        end

        [ key, value ]
      end
    end

    # `platform:` tools are code-defined and shared; an installation that does
    # not have one cannot run the template as written.
    def resolve_platform_tools!(package)
      names = package.section("tools").filter_map { |tool| tool["platform"] }
      found = Tool.code_source.not_deleted.where(name: names).index_by(&:name)
      missing = names - found.keys
      raise NotInstallable, "This installation has no platform tool named #{missing.join(', ')}" if missing.any?

      found
    end

    # `internal:` MCP servers are the platform's own (aixle-tools), shared by every project.
    def resolve_internal_servers!(package)
      names = package.section("mcp_servers").filter_map { |server| server["internal"] }
      found = MCPServer.internal_servers.where(name: names).index_by(&:name)
      missing = names - found.keys
      raise NotInstallable, "This installation has no built-in MCP server named #{missing.join(', ')}" if missing.any?

      found
    end

    # ---- resources --------------------------------------------------------

    def plan_resources(plan)
      MATCHED_SECTIONS.each do |section|
        plan.package.section(section).each do |entry|
          next if section == "tools" && entry["platform"]
          next if section == "mcp_servers" && entry["internal"]

          plan.items << plan_item(plan, section, entry)
        end
      end
      plan.package.section("workflows").each do |workflow|
        plan.items << Item.new(section: "workflows", key: workflow["key"], name: workflow["name"], action: "create",
                               install_name: unique_workflow_name(plan, workflow["name"]))
      end
      plan.package.config_item_names.each do |name|
        existing = plan.project && ConfigItem.for_project(plan.project).find_by(name: name)
        plan.items << Item.new(section: "config_items", key: name, name: name,
                               action: existing ? "reuse" : "create", existing_id: existing&.id)
      end
    end

    def plan_item(plan, section, entry)
      name = resource_name(plan.package, section, entry)
      existing = plan.project && existing_row(plan.project, section, name, entry)
      return Item.new(section: section, key: entry["key"], name: name, action: "create", install_name: name) unless existing
      return Item.new(section: section, key: entry["key"], name: name, action: "reuse", existing_id: existing.id) if same_content?(plan, section, entry, existing)

      case @resolutions["#{section}.#{entry['key']}"]
      when "use_existing" then Item.new(section: section, key: entry["key"], name: name, action: "reuse", existing_id: existing.id)
      when "copy" then Item.new(section: section, key: entry["key"], name: name, action: "copy", existing_id: existing.id,
                                install_name: copy_name(plan.project, section, name))
      else Item.new(section: section, key: entry["key"], name: name, action: "conflict", existing_id: existing.id)
      end
    end

    # The name the resource gets in the project, which is what an existing
    # project is matched on.
    def resource_name(package, section, entry)
      case section
      when "agents", "tools", "assets" then entry["name"]
      when "skills" then Planner.skill_name(package, entry)
      when "mcp_servers" then entry.dig("custom", "name") || connector_manifest(package, entry)["title"].presence || entry.dig("connector", "name")
      end
    end

    def existing_row(project, section, name, entry)
      case section
      when "agents" then project.agents.find_by(name: name)
      when "tools" then Tool.for_project(project).not_deleted.where(scope: project).find_by(name: name)
      when "skills" then Skill.for_project(project).where(scope: project).find_by(name: name)
      when "mcp_servers" then MCPServer.for_project(project).where(scope: project).find_by(name: name)
      when "assets" then project.assets.find_by(name: name, folder: entry["folder"].presence)
      end
    end

    def same_content?(plan, section, entry, row)
      case section
      when "agents"
        %w[title persona principles communication_style].all? { |f| row.public_send(f).to_s == substitute(plan, entry[f]).to_s }
      when "skills" then row.content.to_s == skill_markdown(plan.package, entry).content.to_s
      when "tools"
        row.command == entry["command"] && row.docker_image == entry["docker_image"] &&
          row.tool_files.map { |f| [ f.path, f.content ] }.sort ==
            Array(entry["files"]).map { |f| [ f["path"], plan.package.file(f["from"]).to_s ] }.sort
      when "mcp_servers"
        if entry["connector"]
          row.connector_name == entry.dig("connector", "name") && row.connector_version == entry.dig("connector", "version")
        else
          custom = entry["custom"]
          row.url.to_s == substitute(plan, custom["url"]).to_s && row.transport.to_s == custom["transport"] &&
            row.headers.to_h == custom["headers"].to_h.transform_values { |v| substitute(plan, v) } &&
            row.env.to_h == custom["env"].to_h.transform_values { |v| substitute(plan, v) }
        end
      else false
      end
    end

    def substitute(plan, value) = Substitution.apply(value, plan.inputs)

    def copy_name(project, section, name)
      separator = %w[agents tools].include?(section) ? "_" : " "
      candidates = (2..50).map { |n| separator == "_" ? "#{name}_#{n}" : "#{name} (#{n})" }
      candidates.find { |candidate| existing_row(project, section, candidate, {}).nil? } || "#{name}#{separator}#{SecureRandom.hex(2)}"
    end

    def unique_workflow_name(plan, name)
      return name unless plan.project

      taken = plan.project.workflows.active.where("name = ? OR name LIKE ?", name, "#{Workflow.sanitize_sql_like(name)} (%)").pluck(:name)
      return name if taken.exclude?(name)

      suffix = 2
      suffix += 1 while taken.include?("#{name} (#{suffix})")
      "#{name} (#{suffix})"
    end

    # ---- board ------------------------------------------------------------

    # board_action: create | merge | skip (not the owner) | none (no board in the template).
    # column_map: column key → an existing column id, "create", or nil (unavailable).
    def plan_board(plan)
      columns = Array(plan.package.board&.dig("columns"))
      board = plan.project&.board
      plan.board_action =
        if plan.package.board.nil? then "none"
        elsif plan.project.nil? then "create"
        elsif !Web::Company::Projects::BoardsPolicy.new(ProjectContext.new(@user, {}, project: plan.project), board).update?
          "skip"
        elsif board then "merge"
        else "create"
        end
      plan.warnings << "Only the project owner can change its board, so the board part of this template is skipped." if plan.board_action == "skip"

      columns.each do |column|
        existing = board&.board_columns&.find_by(id: @resolutions["columns.#{column['key']}"]) if @resolutions["columns.#{column['key']}"].present?
        existing ||= board&.board_columns&.find_by(name: column["name"]) if plan.board_action == "merge"
        plan.column_map[column["key"]] = existing&.id || (%w[create merge].include?(plan.board_action) ? "create" : nil)
      end
    end

    # ---- checklist --------------------------------------------------------

    # What the installer will leave for the user. Items resolved later (an
    # OAuth sign-in found by the post-install probe) are added by the installer.
    def plan_checklist(plan)
      plan.package.secrets.each do |secret|
        next if plan.item("config_items", secret["name"])&.action == "reuse" || @provided_secrets.include?(secret["name"])

        plan.checklist << { kind: "secret", ref: "secret:#{secret['name']}", detail: secret.slice("name", "description") }
      end
      connected = plan.project ? Tool.active_integration_providers(plan.project) : company_integration_providers(plan.company)
      Array(plan.package.requires["integrations"]).each do |provider|
        next if connected.include?(provider)

        plan.checklist << { kind: "integration", ref: "integration:#{provider}", detail: { "provider" => provider } }
      end
      Array(plan.package.requires["repositories"]).each do |repo|
        plan.checklist << { kind: "repository", ref: "repository:#{repo['key']}", detail: repo.slice("key", "purpose") }
      end
      plan.package.section("triggers").each_with_index do |trigger, index|
        plan.checklist << { kind: "trigger", ref: "trigger:#{index}", detail: trigger.slice("kind", "workflow", "column", "trigger_mode") }
      end
    end

    def company_integration_providers(company)
      Integration.active.where(company_id: company.id, project_id: nil).distinct.pluck(:provider)
    end

    # ---- package helpers --------------------------------------------------

    def skill_markdown(package, entry)
      path = entry["path"] || entry.dig("snapshot", "path")
      Skills::SkillMarkdown.parse(package.file(path).to_s.dup.force_encoding(Encoding::UTF_8))
    end

    def connector_manifest(package, entry)
      JSON.parse(package.file(entry.dig("connector", "manifest", "path")).to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
