# frozen_string_literal: true

module Templates
  # Installs a catalog template (design §7.3). Everything is created in one
  # transaction from the mirrored package alone — nothing is fetched (D17) — and
  # the only network step, the OAuth probe of the created MCP servers, runs after
  # commit in Templates::ProbeServersJob.
  #
  #   plan = Templates::Installer.new(...).plan     # what the page shows
  #   result = Templates::Installer.new(..., confirmed_digest: plan.digest).apply
  #
  # `apply` re-plans inside the transaction; if the plan moved since the user
  # confirmed it (a same-named agent appeared, the mirror synced a new version)
  # it raises PlanChanged instead of installing something nobody reviewed.
  class Installer
    PlanChanged = Class.new(Planner::Error)
    UnresolvedConflicts = Class.new(Planner::Error)

    Result = Struct.new(:install, :project, :plan, :created, :server_ids, keyword_init: true)

    STEP_SETTINGS = %w[on_failure skip_policy max_retries preferred_model required_agent_runtime
                       allow_non_interactive bmad_enabled input_asset_specs output_asset_specs].freeze

    # @param secrets [Hash{String => String}] secret values typed on the install page
    # @param idempotency_key [String] one per install attempt: a double click or a
    #   retried MCP call returns the first install instead of creating a second
    def initialize(catalog_template:, user:, target:, idempotency_key:, inputs: {}, secrets: {}, resolutions: {},
                   expected: nil, confirmed_digest: nil)
      @catalog_template = catalog_template
      @user = user
      @target = target
      @inputs = inputs
      @secrets = secrets.to_h.transform_keys(&:to_s).compact_blank
      @resolutions = resolutions
      @expected = expected
      @confirmed_digest = confirmed_digest
      @idempotency_key = idempotency_key.to_s
    end

    attr_reader :idempotency_key

    def plan
      Planner.new(catalog_template: @catalog_template, user: @user, target: @target, inputs: @inputs,
                  resolutions: @resolutions, expected: @expected, provided_secrets: @secrets.keys).call
    end

    def apply
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      previous = TemplateInstall.find_by(installed_by: @user, idempotency_key: @idempotency_key)
      return Result.new(install: previous, project: previous.project, created: false) if previous

      result = ActiveRecord::Base.transaction { install!(plan) }
      ProbeServersJob.perform_later(result.install.id, result.server_ids) if result.server_ids.any?
      result
    rescue ActiveRecord::RecordNotUnique
      previous = TemplateInstall.find_by!(installed_by: @user, idempotency_key: @idempotency_key)
      Result.new(install: previous, project: previous.project, created: false)
    end

    private

    def install!(plan)
      raise UnresolvedConflicts, "Resolve every conflict before installing" unless plan.resolved?
      raise PlanChanged, "What this install would do changed since you reviewed it — review it again" if @confirmed_digest && @confirmed_digest != plan.digest

      @plan = plan
      @package = plan.package
      @ids = Hash.new { |h, k| h[k] = {} }
      @project = plan.project || create_project!
      @builder = ProjectResources::Builder.new(@project)

      install = @project.template_installs.create!(
        installed_by: @user, slug: @catalog_template.slug, version: @catalog_template.version,
        commit_sha: @catalog_template.commit_sha, package_digest: @catalog_template.package_digest,
        idempotency_key: @idempotency_key
      )

      create_config_items
      create_board
      create_assets
      create_agents
      create_skills
      create_tools
      create_mcp_servers
      create_workflows
      triggers = create_triggers
      create_setup_items(install, triggers)
      @catalog_template.increment!(:install_count)

      created_servers = @package.section("mcp_servers").reject { |e| e["internal"] || planned("mcp_servers", e["key"]).action == "reuse" }
      Result.new(install: install, project: @project, plan: plan, created: true,
                 server_ids: created_servers.map { |e| @ids["mcp_servers"][e["key"]] })
    end

    def create_project!
      @plan.company.projects.create!(
        name: @plan.project_name, owner: @user,
        description: substitute(@package.definition.dig("project", "description")),
        preferred_artifacts_language: @package.definition.dig("project", "preferred_artifacts_language").presence || "en"
      )
    end

    def substitute(value) = Substitution.apply(value, @plan.inputs)

    # Returns the id to reference for a package key: the reused row, or the one
    # created for it. nil when the item was not planned.
    def planned(section, key) = @plan.item(section, key)

    def install_name(section, key) = planned(section, key).install_name

    def reuse?(section, key)
      item = planned(section, key)
      @ids[section][key] = item.existing_id if item.action == "reuse"
      item.action == "reuse"
    end

    # ---- config items -----------------------------------------------------

    def create_config_items
      @package.variables.each do |variable|
        next if reuse?("config_items", variable["name"])

        @ids["config_items"][variable["name"]] = @project.config_items.create!(
          name: variable["name"], item_type: "variable", value: substitute(variable["value"]),
          description: variable["description"]
        ).id
      end
      @package.secrets.each do |secret|
        next if reuse?("config_items", secret["name"])
        next if @secrets[secret["name"]].blank?

        @ids["config_items"][secret["name"]] = @project.config_items.create!(
          name: secret["name"], item_type: "secret", value: @secrets[secret["name"]], description: secret["description"]
        ).id
      end
    end

    # ---- board ------------------------------------------------------------

    def create_board
      board = @project.board
      columns = Array(@package.board&.dig("columns"))
      to_create = columns.select { |column| @plan.column_map[column["key"]] == "create" }
      case @plan.board_action
      when "create"
        board = Board.create_from_columns(project: @project, name: @package.board["name"].presence || "Board",
                                          columns: to_create.map { |c| board_column_attributes(c) })
      when "merge"
        position = board.board_columns.maximum(:position).to_i
        to_create.each { |column| board.board_columns.create!(board_column_attributes(column).merge(position: position += 1)) }
      end

      columns.each do |column|
        target = @plan.column_map[column["key"]]
        @ids["columns"][column["key"]] = target == "create" ? board.board_columns.find_by!(name: column["name"]).id : target
      end
    end

    def board_column_attributes(column) = { name: column["name"], purpose: substitute(column["purpose"]) }

    # ---- resources --------------------------------------------------------

    def create_assets
      @package.section("assets").each do |entry|
        next if reuse?("assets", entry["key"])

        asset = @project.assets.create!(name: install_name("assets", entry["key"]), folder: entry["folder"].presence,
                                        tags: Array(entry["tags"]), created_by: @user)
        attach_file(asset, entry["path"])
        @ids["assets"][entry["key"]] = asset.id
      end
    end

    def attach_file(asset, path)
      bytes = @package.file(path)
      filename = File.basename(path)
      file = Tempfile.new([ "template-asset-", File.extname(filename) ])
      file.binmode
      file.write(bytes)
      file.rewind
      file.define_singleton_method(:original_filename) { filename }
      AssetVersion.create!(asset: asset, uploaded_by: @user, file: file, file_size: bytes.bytesize,
                           content_type: Marcel::MimeType.for(name: filename))
    ensure
      file&.close!
    end

    def create_agents
      @package.section("agents").each do |entry|
        next if reuse?("agents", entry["key"])

        attrs = entry.slice("title", "icon").merge(
          "name" => install_name("agents", entry["key"]),
          "persona" => substitute(entry["persona"]),
          "principles" => substitute(entry["principles"]),
          "communication_style" => substitute(entry["communication_style"])
        )
        @ids["agents"][entry["key"]] = @builder.agent!(attrs).id
      end
    end

    def create_skills
      @package.section("skills").each do |entry|
        next if reuse?("skills", entry["key"])

        path = entry["path"] || entry.dig("snapshot", "path")
        content = @package.file(path).to_s.dup.force_encoding(Encoding::UTF_8)
        markdown = Skills::SkillMarkdown.parse(content)
        attrs = { name: install_name("skills", entry["key"]), title: markdown.name || entry["key"],
                  description: markdown.description, content: markdown.content }
        if entry["registry"]
          source = entry["registry"].split("@").first
          attrs.merge!(origin: "registry", package: entry["registry"], source: source,
                       source_url: "https://github.com/#{source}", content_hash: entry.dig("snapshot", "sha256"))
        else
          attrs[:origin] = "manual"
        end
        @ids["skills"][entry["key"]] = @builder.skill!(attrs).id
      end
    end

    def create_tools
      @package.section("tools").each do |entry|
        if entry["platform"]
          @ids["tools"][entry["key"]] = @plan.platform_tools.fetch(entry["platform"]).id
          next
        end
        next if reuse?("tools", entry["key"])

        attrs = entry.slice("display_name", "description", "docker_image", "command", "input_schema",
                            "required_config_items", "requires_integration")
                     .merge("name" => install_name("tools", entry["key"]), "execution_mode" => "container")
        files = Array(entry["files"]).map { |f| { path: f["path"], content: @package.file(f["from"]).to_s } }
        @ids["tools"][entry["key"]] = @builder.tool!(attrs, files: files).id
      end
    end

    def create_mcp_servers
      @package.section("mcp_servers").each do |entry|
        if entry["internal"]
          @ids["mcp_servers"][entry["key"]] = @plan.internal_servers.fetch(entry["internal"]).id
          next
        end
        next if reuse?("mcp_servers", entry["key"])

        @ids["mcp_servers"][entry["key"]] = (entry["connector"] ? install_connector(entry) : install_custom_server(entry)).id
      end
    end

    def install_connector(entry)
      connector = entry["connector"]
      manifest = JSON.parse(@package.file(connector.dig("manifest", "path")))
      MCP::ConnectorInstaller.create_from_manifest(
        project: @project, manifest: manifest, target_id: connector["target"],
        values: connector["values"].to_h.transform_values { |v| substitute(v) }, fallback_name: connector["name"]
      )
    end

    def install_custom_server(entry)
      custom = entry["custom"]
      @builder.mcp_server!(
        name: install_name("mcp_servers", entry["key"]),
        description: custom["description"], transport: custom["transport"],
        url: substitute(custom["url"]), command: custom["command"],
        args: Array(custom["args"]).map { |arg| substitute(arg) },
        headers: custom["headers"].to_h.transform_values { |v| substitute(v) },
        env: custom["env"].to_h.transform_values { |v| substitute(v) },
        auth_type: custom["auth_type"].presence || "none"
      )
    end

    # ---- workflows --------------------------------------------------------

    def create_workflows
      @package.section("workflows").each do |entry|
        base = entry["base"].to_h
        workflow = @project.workflows.create!(
          name: install_name("workflows", entry["key"]), description: substitute(entry["description"]),
          config: {
            "base_tool_ids" => ids("tools", base["tools"]), "base_skill_ids" => ids("skills", base["skills"]),
            "base_mcp_server_ids" => ids("mcp_servers", base["mcp_servers"]),
            "base_asset_ids" => ids("assets", base["assets"]),
            "base_config_item_ids" => ids("config_items", base["config_items"]),
            "base_repository_ids" => [], "inherit_all_project_resources" => false
          }
        )
        @ids["workflows"][entry["key"]] = workflow.id
        create_steps(workflow, entry["steps"])
      end
    end

    def create_steps(workflow, entries)
      steps = entries.each_with_index.to_h do |entry, index|
        step = workflow.steps.create!(
          entry.slice(*STEP_SETTINGS).merge(
            "name" => entry["name"], "position" => index + 1, "instructions" => substitute(entry["instructions"]),
            "agent_id" => entry["agent"] && @ids["agents"].fetch(entry["agent"]),
            "tool_ids" => ids("tools", entry["tools"]), "skill_ids" => ids("skills", entry["skills"]),
            "mcp_server_ids" => ids("mcp_servers", entry["mcp_servers"]), "asset_ids" => ids("assets", entry["assets"]),
            "config_item_ids" => ids("config_items", entry["config_items"]), "repository_ids" => []
          )
        )
        Array(entry["sub_steps"]).each_with_index do |sub, sub_index|
          step.sub_steps.create!(name: sub["name"], instructions: substitute(sub["instructions"]),
                                 required: sub.fetch("required", true), position: sub_index + 1)
        end
        [ entry["key"], step ]
      end
      entries.each do |entry|
        next if entry["depends_on"].blank?

        steps[entry["key"]].update!(depends_on_step_ids: entry["depends_on"].map { |key| steps.fetch(key).id })
      end
    end

    # Keys whose resource was not created (a secret with no value yet) are left
    # out; the checklist fills them in when the user adds the value.
    def ids(section, keys) = Array(keys).filter_map { |key| @ids[section][key] }

    # ---- triggers ---------------------------------------------------------

    # Every trigger is installed inactive (D8): event triggers disabled, column
    # triggers manual. Returns index → created trigger (nil when it could not be
    # created, e.g. its column was not available).
    def create_triggers
      @package.section("triggers").each_with_index.to_h do |entry, index|
        [ index, create_trigger(entry) ]
      end
    end

    def create_trigger(entry)
      workflow = Workflow.find(@ids["workflows"].fetch(entry["workflow"]))
      if entry["kind"] == "column"
        column_id = @ids["columns"][entry["column"]]
        return nil unless column_id

        attributes = { board_column_id: column_id, trigger_mode: "manual", cooldown_seconds: entry["cooldown_seconds"] }
      else
        attributes = entry.slice("name", "event_type", "trigger_mode", "subject_policy", "filter_predicate",
                                 "cooldown_seconds", "notify_on_failure", "verification_strategy").symbolize_keys
        attributes[:enabled] = false
        attributes[:subject_title_template] = substitute(entry["subject_title_template"]) if entry["subject_title_template"]
        attributes[:subject_column_id] = @ids["columns"][entry["subject_column"]] if entry["subject_column"]
        attributes[:schedule_config] = { "cron" => substitute(entry["cron"]), "timezone" => entry["timezone"].presence || "UTC" } if entry["cron"]
      end
      WorkflowTriggers::Creator.call(project: @project, workflow: workflow, user: @user, kind: entry["kind"],
                                     attributes: attributes.compact)
    end

    # ---- checklist --------------------------------------------------------

    def create_setup_items(install, triggers)
      @plan.checklist.each_with_index do |item, position|
        detail = item[:detail].merge(checklist_detail(item, triggers))
        install.setup_items.create!(kind: item[:kind], ref: item[:ref], position: position, detail: detail)
      end
      if @plan.board_action == "skip"
        install.setup_items.create!(kind: "board", ref: "board", position: @plan.checklist.size,
                                    detail: { "reason" => "Only the project owner can apply the template's board." })
      end
    end

    # Where the item's value has to be attached once the user provides it.
    def checklist_detail(item, triggers)
      case item[:kind]
      when "secret" then { "attach_to" => attach_targets { |refs| refs["config_items"].include?(item[:detail]["name"]) } }
      when "repository" then { "attach_to" => attach_targets { |refs| refs["repositories"].include?(item[:detail]["key"]) } }
      when "trigger" then trigger_detail(item, triggers)
      else {}
      end
    end

    def trigger_detail(item, triggers)
      index = item[:ref].delete_prefix("trigger:").to_i
      entry = @package.section("triggers")[index]
      result = triggers[index]
      return { "missing" => "No board column to bind to" } unless result

      { "record" => result.kind == "column" ? "column" : "binding", "trigger_id" => result.trigger.id,
        "activate_mode" => entry["trigger_mode"].presence || "auto",
        "webhook_endpoint_id" => result.webhook_endpoint&.id }.compact
    end

    # workflow and step ids whose package entry references the thing
    def attach_targets
      targets = { "workflow_ids" => [], "step_ids" => [] }
      @package.section("workflows").each do |entry|
        workflow = Workflow.find(@ids["workflows"][entry["key"]])
        targets["workflow_ids"] << workflow.id if yield(normalize_refs(entry["base"].to_h))
        entry["steps"].each do |step|
          next unless yield(normalize_refs(step))

          targets["step_ids"] << workflow.steps.find_by!(position: entry["steps"].index(step) + 1).id
        end
      end
      targets
    end

    def normalize_refs(hash) = { "config_items" => Array(hash["config_items"]), "repositories" => Array(hash["repositories"]) }
  end
end
