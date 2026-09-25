# frozen_string_literal: true

module Templates
  # Turns a working project — or some of its workflows — into a template
  # package (design §6.2). Fails closed: anything that cannot be carried
  # faithfully aborts the export with a named reason instead of being dropped,
  # because a package that validates but behaves differently from its source
  # is worse than no package.
  #
  # What never leaves: secret values (only names), integration credentials,
  # repository identities, webhook secrets, cards, comments, runs.
  class Exporter
    ExportError = Class.new(StandardError) do
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join("; "))
      end
    end

    Result = Struct.new(:package, :template_yaml, :notes, keyword_init: true)

    CONFIG_ITEM_REF = /config_item:([A-Z][A-Z0-9_]*)/

    # @param workflow_ids [Array<Integer>, nil] nil exports every workflow, [] none
    # @param agent_ids / skill_ids [Array<Integer>] exported even when no workflow uses them —
    #   how an agent or skill template is made
    def initialize(project:, namespace:, slug:, name:, workflow_ids: nil, agent_ids: [], skill_ids: [], include_board: true,
                   include_assets: false, summary: nil)
      @project = project
      @namespace = namespace
      @slug = slug
      @name = name
      @summary = summary
      @workflow_ids = workflow_ids
      @agent_ids = Array(agent_ids)
      @skill_ids = Array(skill_ids)
      @include_board = include_board
      @include_assets = include_assets
      @errors = []
      @notes = []
      @files = {}
      @keys = Hash.new { |h, k| h[k] = {} } # section → record id → key
      @config_item_names_used = Set.new
    end

    def call
      definition = build_definition
      raise ExportError, @errors if @errors.any?

      package = Package.new(definition: definition, files: @files)
      Validator.validate!(package)
      Result.new(package: package, template_yaml: definition.to_yaml.delete_prefix("---\n"), notes: @notes)
    rescue Validator::InvalidPackage => e
      raise ExportError, e.errors
    end

    private

    def build_definition
      definition = { "format_version" => Package::FORMAT_VERSION, "namespace" => @namespace, "slug" => @slug,
                     "version" => 1, "name" => @name }
      definition["summary"] = @summary if @summary.present?
      workflows = export_workflows
      @agent_ids.each { |id| agent_key(id, "agent #{id}") }
      @skill_ids.each { |id| skill_key(id, "skill #{id}") }
      definition["board"] = export_board if @include_board && @project.board
      definition["agents"] = @agents.values if @agents.any?
      definition["skills"] = @skills.values if @skills.any?
      definition["mcp_servers"] = @servers.values if @servers.any?
      definition["tools"] = @tools.values if @tools.any?
      definition["assets"] = @assets.values if @assets.any?
      definition["workflows"] = workflows if workflows.any?
      triggers = export_triggers
      definition["triggers"] = triggers if triggers.any?
      variables, secrets = export_config_items
      definition["variables"] = variables if variables.any?
      requires = export_requires(secrets)
      definition["requires"] = requires if requires.any?
      definition
    end

    # ---- workflows --------------------------------------------------------

    def workflows_scope
      scope = @project.workflows.active.order(:id)
      @workflow_ids ? scope.where(id: @workflow_ids) : scope
    end

    def export_workflows
      @agents = {}
      @skills = {}
      @servers = {}
      @tools = {}
      @assets = {}
      @config_item_ids = Set.new
      @repository_ids = Set.new

      workflows_scope.map do |workflow|
        key = key_for("workflows", workflow.id, workflow.name)
        base = base_resources(workflow)
        {
          "key" => key, "name" => workflow.name, "description" => workflow.description,
          "base" => {
            "tools" => base[:tools].filter_map { |id| tool_key(id, "workflow #{workflow.name} base") },
            "skills" => base[:skills].filter_map { |id| skill_key(id, "workflow #{workflow.name} base") },
            "mcp_servers" => base[:mcp_servers].filter_map { |id| server_key(id, "workflow #{workflow.name} base") },
            "assets" => base[:assets].filter_map { |id| asset_key(id, "workflow #{workflow.name} base") },
            "config_items" => base[:config_items].filter_map { |id| config_item_name(id, "workflow #{workflow.name} base") },
            "repositories" => base[:repositories].filter_map { |id| repository_key(id) }
          }.reject { |_, v| v.empty? },
          "steps" => export_steps(workflow)
        }.compact.reject { |k, v| k == "base" && v.empty? }
      end
    end

    # inherit_all_project_resources is flattened: the installed workflow gets
    # exactly what this project had, not whatever the target project contains.
    def base_resources(workflow)
      if workflow.inherit_all_project_resources
        @notes << "Workflow #{workflow.name} inherited every project resource; the export lists them explicitly."
        {
          tools: Tool.for_project(@project).not_deleted.where(scope: @project).pluck(:id),
          skills: @project.skills.pluck(:id), mcp_servers: @project.mcp_servers.pluck(:id),
          assets: [], config_items: @project.config_items.pluck(:id), repositories: @project.repositories.pluck(:id)
        }
      else
        { tools: workflow.base_tool_ids, skills: workflow.base_skill_ids, mcp_servers: workflow.base_mcp_server_ids,
          assets: workflow.base_asset_ids, config_items: workflow.base_config_item_ids,
          repositories: workflow.base_repository_ids }
      end
    end

    STEP_SETTINGS = Installer::STEP_SETTINGS

    def export_steps(workflow)
      steps = workflow.steps.not_deleted.order(:position).to_a
      step_keys = steps.to_h { |step| [ step.id, key_for("steps:#{workflow.id}", step.id, step.name) ] }
      steps.map do |step|
        where = "workflow #{workflow.name} step #{step.name}"
        entry = { "key" => step_keys[step.id], "name" => step.name, "instructions" => step.instructions }
        entry["agent"] = agent_key(step.agent_id, where) if step.agent_id
        entry["tools"] = step.tool_ids.filter_map { |id| tool_key(id, where) }
        entry["skills"] = step.skill_ids.filter_map { |id| skill_key(id, where) }
        entry["mcp_servers"] = step.mcp_server_ids.filter_map { |id| server_key(id, where) }
        entry["assets"] = step.asset_ids.filter_map { |id| asset_key(id, where) }
        entry["config_items"] = step.config_item_ids.filter_map { |id| config_item_name(id, where) }
        entry["repositories"] = step.repository_ids.filter_map { |id| repository_key(id) }
        entry["depends_on"] = step.depends_on_step_ids.filter_map do |id|
          step_keys[id] || unresolved("#{where} depends on a step outside this workflow")
        end
        STEP_SETTINGS.each { |field| entry[field] = step.public_send(field) }
        entry["on_failure"] = entry["on_failure"].to_s
        entry["skip_policy"] = entry["skip_policy"].to_s
        entry["sub_steps"] = step.sub_steps.active.order(:position).map do |sub|
          { "name" => sub.name, "instructions" => sub.instructions, "required" => sub.required }.compact
        end
        entry.reject { |_, v| v.nil? || v == [] || v == "" }
      end
    end

    # ---- resources --------------------------------------------------------

    def agent_key(id, where)
      agent = @project.agents.find_by(id: id) or return unresolved("#{where}: its agent is not in this project")
      key = key_for("agents", agent.id, agent.name)
      @agents[agent.id] ||= { "key" => key, "name" => agent.name, "title" => agent.title, "icon" => agent.icon,
                              "persona" => agent.persona, "principles" => agent.principles,
                              "communication_style" => agent.communication_style }.compact
      key
    end

    def skill_key(id, where)
      skill = @project.skills.find_by(id: id) or return unresolved("#{where}: skill #{id} is not in this project")
      key = key_for("skills", skill.id, skill.name)
      @skills[skill.id] ||=
        if skill.registry? && skill.package.present?
          path = "snapshots/skills/#{key}.md"
          @files[path] = skill.content.to_s
          { "key" => key, "registry" => skill.package, "snapshot" => { "path" => path, "sha256" => sha(path) } }
        else
          path = "skills/#{key}/SKILL.md"
          @files[path] = skill.content.to_s
          { "key" => key, "path" => path }
        end
      key
    end

    def server_key(id, where)
      server = MCPServer.find_by(id: id) or return unresolved("#{where}: MCP server #{id} no longer exists")
      if server.internal?
        key = key_for("mcp_servers", server.id, server.name)
        @servers[server.id] ||= { "key" => key, "internal" => server.name }
        return key
      end
      return unresolved("#{where}: MCP server #{server.name} belongs to another project") unless server.scope == @project

      key = key_for("mcp_servers", server.id, server.name)
      @servers[server.id] ||= server.connector_name.present? ? connector_entry(server, key) : custom_server_entry(server, key)
      key
    end

    def connector_entry(server, key)
      manifest = server.connector_manifest.to_h.except("installed_target")
      target = server.connector_manifest.to_h["installed_target"].to_h
      path = "snapshots/connectors/#{key}.json"
      @files[path] = "#{JSON.pretty_generate(manifest)}\n"
      values = templated_inputs(server, target)
      { "key" => key, "connector" => { "name" => server.connector_name, "version" => server.connector_version.to_s,
                                       "target" => target["id"].to_s,
                                       "manifest" => { "path" => path, "sha256" => sha(path) },
                                       "values" => values.presence }.compact }
    end

    # A connector's header/env values are keyed by the manifest's input keys,
    # so they export as `values` — provided each is a config item reference.
    def templated_inputs(server, target)
      Array(target["inputs"]).each_with_object({}) do |input, values|
        value = (input["kind"] == "env" ? server.env : server.headers).to_h[input["key"]]
        next if value.blank?

        if input["value_template"].present?
          unresolved("MCP server #{server.name}: input #{input['key']} is built from a template and cannot be exported; " \
                     "set it to a config_item: reference first")
        else
          values[input["key"]] = reference_or_error(server, input["key"], value)
        end
      end
    end

    def custom_server_entry(server, key)
      custom = { "name" => server.name, "description" => server.description, "transport" => server.transport.to_s,
                 "url" => server.url, "command" => server.command, "args" => server.args.presence,
                 "headers" => server.headers.to_h.to_h { |k, v| [ k, reference_or_error(server, k, v) ] }.presence,
                 "env" => server.env.to_h.to_h { |k, v| [ k, reference_or_error(server, k, v) ] }.presence,
                 "auth_type" => server.auth_type.to_s }.compact
      { "key" => key, "custom" => custom }
    end

    # Fail closed: a literal value might be a secret, and the exporter does not guess.
    def reference_or_error(server, name, value)
      value.to_s.scan(CONFIG_ITEM_REF).flatten.each { |ref| @config_item_names_used << ref }
      return value if value.to_s.match?(Validator::REFERENCE_VALUE)

      unresolved("MCP server #{server.name}: #{name} holds a literal value — store it as a config item and use " \
                 "config_item:NAME, then export again")
      nil
    end

    def tool_key(id, where)
      tool = Tool.find_by(id: id) or return unresolved("#{where}: tool #{id} no longer exists")
      key = key_for("tools", tool.id, tool.name)
      if tool.platform_tool?
        @tools[tool.id] ||= { "key" => key, "platform" => tool.name }
        return key
      end
      return unresolved("#{where}: tool #{tool.name} belongs to another project") unless tool.scope == @project

      @tools[tool.id] ||= custom_tool_entry(tool, key)
      key
    end

    def custom_tool_entry(tool, key)
      unless tool.docker_image.to_s.match?(/@sha256:\h{64}\z/)
        unresolved("tool #{tool.name}: its image #{tool.docker_image} is not pinned by digest (image@sha256:…)")
      end
      files = tool.tool_files.map do |file|
        if file.content.nil? && file.file_data.present?
          unresolved("tool #{tool.name}: binary file #{file.path} cannot be exported yet")
          next
        end
        from = "tools/#{key}/#{file.path.delete_prefix('/workspace/')}"
        @files[from] = file.content.to_s
        { "path" => file.path, "from" => from }
      end.compact
      { "key" => key, "name" => tool.name, "display_name" => tool.display_name, "description" => tool.description,
        "execution_mode" => "container", "docker_image" => tool.docker_image, "command" => tool.command,
        "input_schema" => tool.input_schema.presence, "required_config_items" => tool.required_config_items.presence,
        "requires_integration" => tool.requires_integration, "files" => files.presence }.compact
    end

    def asset_key(id, where)
      asset = Asset.find_by(id: id)
      return unresolved("#{where}: asset #{id} no longer exists") unless asset
      if asset.scope_type == "Company"
        @notes << "Company asset #{asset.name} is shared by the company and is not exported."
        return nil
      end
      return unresolved("#{where}: uses asset #{asset.name} — export with include_assets") unless @include_assets

      key = key_for("assets", asset.id, asset.name)
      @assets[asset.id] ||= begin
        version = asset.versions.order(:version).last
        path = "assets/#{key}/#{version&.file&.original_filename.presence || asset.name}"
        @files[path] = version&.file&.read.to_s
        { "key" => key, "name" => asset.name, "folder" => asset.folder.presence, "path" => path,
          "tags" => asset.tags.presence }.compact
      end
      key
    end

    def config_item_name(id, where)
      item = ConfigItem.find_by(id: id, scope: @project) or return unresolved("#{where}: config item #{id} is not in this project")
      @config_item_ids << item.id
      item.name
    end

    def repository_key(id)
      repository = @project.repositories.find_by(id: id) or return nil
      @repository_ids << repository.id
      key_for("repositories", repository.id, repository.full_name.split("/").last)
    end

    # ---- board, triggers, config, requirements ----------------------------

    def export_board
      board = @project.board
      { "name" => board.name,
        "columns" => board.board_columns.map do |column|
          { "key" => key_for("columns", column.id, column.name), "name" => column.name, "purpose" => column.purpose.presence }.compact
        end }
    end

    def export_triggers
      workflow_ids = @keys["workflows"].keys
      column_triggers = ColumnWorkflowBinding.joins(board_column: :board)
                                             .where(boards: { project_id: @project.id }, workflow_id: workflow_ids)
      bindings = TriggerBinding.where(project: @project, workflow_id: workflow_ids).order(:id)
      triggers = []
      if @include_board
        triggers += column_triggers.map do |binding|
          { "kind" => "column", "workflow" => @keys["workflows"][binding.workflow_id],
            "column" => @keys["columns"][binding.board_column_id], "trigger_mode" => binding.trigger_mode.to_s,
            "cooldown_seconds" => binding.cooldown_seconds }
        end
      elsif column_triggers.any?
        @notes << "Column triggers are left out because the board is not exported."
      end
      triggers + bindings.map { |binding| binding_entry(binding) }
    end

    def binding_entry(binding)
      kind = case binding.event_type
      when "slack.message" then "slack"
      when "schedule.fired" then "schedule"
      when /\Awebhook\./ then "webhook"
      else "event"
      end
      entry = { "kind" => kind, "workflow" => @keys["workflows"][binding.workflow_id], "name" => binding.name,
                "trigger_mode" => binding.trigger_mode.to_s, "subject_policy" => binding.subject_policy.to_s,
                "subject_title_template" => binding.subject_title_template,
                "filter_predicate" => binding.filter_predicate.presence, "cooldown_seconds" => binding.cooldown_seconds,
                "notify_on_failure" => binding.notify_on_failure }
      entry["event_type"] = binding.event_type if kind == "event"
      entry["cron"] = binding.schedule_config["cron"] if kind == "schedule"
      entry["timezone"] = binding.schedule_config["timezone"].presence if kind == "schedule"
      entry["subject_column"] = @keys["columns"][binding.subject_column_id] if binding.subject_column_id && @include_board
      if kind == "webhook"
        endpoint = WebhookEndpoint.where(project: @project).find { |e| e.config["event_type"] == binding.event_type }
        entry["verification_strategy"] = endpoint&.verification_strategy.to_s.presence
        @notes << "Webhook trigger #{binding.name || binding.id}: its URL and secret are not exported; the installer gets a new endpoint."
      end
      entry.compact
    end

    def export_config_items
      items = ConfigItem.where(id: @config_item_ids.to_a).or(ConfigItem.for_project(@project).where(name: @config_item_names_used.to_a))
      items += Tool.where(id: @tools.keys).flat_map { |tool| ConfigItem.for_project(@project).where(name: Array(tool.required_config_items)).to_a }
      items = items.uniq(&:id).sort_by(&:name)
      variables = items.select(&:variable?).map do |item|
        @notes << "Variable #{item.name} is exported with its value — turn it into an {{inputs.*}} placeholder if it is specific to this project."
        { "name" => item.name, "value" => item.value.to_s, "description" => item.description.presence }.compact
      end
      secrets = items.select(&:secret?).map { |item| { "name" => item.name, "description" => item.description.presence }.compact }
      # Referenced but not in the project yet — the state a template install leaves
      # until the user adds the value. Declared as a secret: the safe assumption.
      referenced = @config_item_names_used.to_a + Tool.where(id: @tools.keys).flat_map { |tool| Array(tool.required_config_items) }
      (referenced.uniq - items.map(&:name)).sort.each do |name|
        @notes << "#{name} is referenced but has no value in this project; it is exported as a secret the installer asks for."
        secrets << { "name" => name }
      end
      [ variables, secrets ]
    end

    def export_requires(secrets)
      integrations = Tool.where(id: @tools.keys).filter_map(&:requires_integration)
      integrations += Repository.where(id: @repository_ids.to_a).filter_map { |r| r.integration&.provider&.to_s }
      repositories = Repository.where(id: @repository_ids.to_a).map do |repository|
        { "key" => @keys["repositories"][repository.id], "purpose" => repository.purpose.presence }.compact
      end
      { "integrations" => integrations.uniq.presence, "repositories" => repositories.presence,
        "secrets" => secrets.presence }.compact
    end

    # ---- helpers ----------------------------------------------------------

    def key_for(section, id, name)
      @keys[section][id] ||= begin
        base = name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
        base = "x_#{base}" unless base.match?(/\A[a-z]/)
        base = base.first(60)
        taken = @keys[section].values
        candidate = base
        n = 1
        candidate = "#{base}_#{n += 1}" while taken.include?(candidate)
        candidate
      end
    end

    def sha(path) = Digest::SHA256.hexdigest(@files[path])

    def unresolved(message)
      @errors << message
      nil
    end
  end
end
