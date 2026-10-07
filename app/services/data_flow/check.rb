# frozen_string_literal: true

module DataFlow
  # What would go wrong with a workflow's files and references at run time, found
  # while it is still being edited (docs/design/at-references.md §6). It reads a
  # saved workflow, or the builder's unsaved payload, as one graph: the sessions,
  # their "Run after" edges, their declared inputs and outputs, their attached
  # assets and MCP servers, and the `@` references in their instructions.
  #
  # Errors are what fails a run for certain; warnings are what probably will.
  # Neither blocks a save. WorkflowService.enqueue refuses a run with errors.
  class Check
    Node = Data.define(:key, :name, :instructions, :depends_on, :asset_ids, :mcp_server_ids, :inputs, :outputs)

    Issue = Data.define(:severity, :code, :step_key, :field, :message, :token, :fix) do
      def error? = severity == "error"

      def as_json(*)
        { severity: severity, code: code, stepKey: step_key, field: field, message: message,
          token: token, fix: fix }.compact
      end
    end

    # The checks a step's own launch repeats (PrepareStepActivity): a reference
    # that cannot be honoured fails the step before its session starts.
    REFERENCE_CODES = %w[ref_missing ref_not_attached output_not_upstream output_undeclared].freeze

    SPEC_FIELDS = { inputs: [ "inputAssetSpecs", "input" ], outputs: [ "outputAssetSpecs", "output" ] }.freeze

    def self.for_workflow(workflow, project:, run_input_asset_ids: nil)
      nodes = workflow.steps.not_deleted.order(:position).map do |step|
        Node.new(key: step.id.to_s, name: step.name, instructions: step.instructions.to_s,
                 depends_on: Array(step.depends_on_step_ids).map(&:to_s),
                 asset_ids: integers(step.asset_ids), mcp_server_ids: integers(step.mcp_server_ids),
                 inputs: step.input_specs, outputs: step.output_specs)
      end
      new(project: project, nodes: nodes, config: workflow.config.to_h, run_input_asset_ids: run_input_asset_ids)
    end

    # @param payload [Hash] the builder's Save body (WorkflowAggregateSave)
    def self.for_payload(workflow, payload, project:)
      payload = payload.to_h.deep_stringify_keys
      nodes = Array(payload["steps"]).map do |step|
        Node.new(key: (step["key"].presence || step["id"]).to_s, name: step["name"].to_s,
                 instructions: step["instructions"].to_s,
                 depends_on: Array(step["depends_on_step_ids"]).map(&:to_s),
                 asset_ids: integers(step["asset_ids"]), mcp_server_ids: integers(step["mcp_server_ids"]),
                 inputs: AssetSpec.list(step["input_asset_specs"]), outputs: AssetSpec.list(step["output_asset_specs"]))
      end
      new(project: project, nodes: nodes, config: workflow.config.to_h.merge(payload["config"].to_h))
    end

    def self.integers(ids) = Array(ids).compact_blank.map(&:to_i)

    # @param run_input_asset_ids [Array<Integer>, nil] the files picked for a run
    #   about to start; nil while editing, when nobody knows them yet
    def initialize(project:, nodes:, config:, run_input_asset_ids: nil)
      @project = project
      @nodes = nodes
      @by_key = nodes.index_by(&:key)
      @graph = Graph.new(nodes.to_h { |node| [ node.key, node.depends_on ] })
      @base_asset_ids = self.class.integers(config["base_asset_ids"])
      @base_mcp_server_ids = self.class.integers(config["base_mcp_server_ids"])
      @inherit_all = ActiveModel::Type::Boolean.new.cast(config["inherit_all_project_resources"]) || false
      @run_input_asset_ids = run_input_asset_ids && self.class.integers(run_input_asset_ids)
    end

    def issues
      @issues ||= @nodes.flat_map do |node|
        upstream = @graph.upstream(node.key)
        reference_issues(node, upstream) + brace_issues(node) + spec_issues(node) +
          input_issues(node, upstream) + collision_issues(node, upstream)
      end
    end

    def errors = issues.select(&:error?)

    def warnings = issues.reject(&:error?)

    private

    # ---- references ---------------------------------------------------------

    def reference_issues(node, upstream)
      InstructionReferences.scan(node.instructions).uniq(&:text).filter_map do |ref|
        unless ref.valid?
          next issue(node, "error", "ref_missing", "instructions",
                     "#{quote(node)} has a reference that cannot be read: #{ref.text}", ref)
        end

        case ref.type
        when "asset" then asset_issue(node, ref)
        when "mcp" then server_issue(node, ref)
        when "step" then step_issue(node, ref, upstream)
        when "output" then output_issue(node, ref, upstream)
        end
      end
    end

    def asset_issue(node, ref)
      asset = assets[ref.id]
      unless asset
        return issue(node, "error", "ref_missing", "instructions",
                     "#{quote(node)} references an asset that was deleted or is not in this project (##{ref.id}).", ref)
      end
      return nil if available_asset_ids(node).include?(asset.id)

      issue(node, "error", "ref_not_attached", "instructions",
            "#{quote(node)} references #{asset.picker_name}, which is not attached to it.", ref,
            fix: { kind: "attach_asset", assetId: asset.id })
    end

    def server_issue(node, ref)
      server = servers[ref.id]
      unless server
        return issue(node, "error", "ref_missing", "instructions",
                     "#{quote(node)} references an MCP server that was removed, disabled or is not in this project (##{ref.id}).", ref)
      end
      return nil if available_server_ids(node).include?(server.id)

      issue(node, "error", "ref_not_attached", "instructions",
            "#{quote(node)} references MCP server #{server.name}, which is not attached to it.", ref,
            fix: { kind: "attach_mcp_server", mcpServerId: server.id })
    end

    def step_issue(node, ref, upstream)
      target = @by_key[ref.id]
      unless target
        return issue(node, "error", "ref_missing", "instructions",
                     "#{quote(node)} references a session that is no longer in this workflow.", ref)
      end
      return nil if target.key == node.key || upstream.include?(target.key)

      issue(node, "warning", "step_not_upstream", "instructions",
            "#{quote(node)} mentions #{quote(target)}, which does not run before it, so its results are not available yet.",
            ref, fix: dependency_fix(node, target))
    end

    def output_issue(node, ref, upstream)
      producer = @by_key[ref.id]
      unless producer
        return issue(node, "error", "ref_missing", "instructions",
                     "#{quote(node)} references an output of a session that is no longer in this workflow.", ref)
      end
      name = AssetSpec.normalize_name(ref.name)
      unless producer.outputs.any? { |spec| spec.plain? && spec.name == name }
        return issue(node, "error", "output_undeclared", "instructions",
                     "#{quote(node)} references #{name}, which #{quote(producer)} does not declare as an output.", ref)
      end
      return nil if producer.key == node.key || upstream.include?(producer.key)

      issue(node, "error", "output_not_upstream", "instructions",
            "#{quote(node)} reads #{name} from #{quote(producer)}, which does not run before it.", ref,
            fix: dependency_fix(node, producer))
    end

    # Adding the edge is the fix unless the target already runs after this
    # session — then the edge would close a cycle.
    def dependency_fix(node, target)
      return nil if @graph.upstream(target.key).include?(node.key)

      { kind: "add_dependency", stepKey: target.key }
    end

    def brace_issues(node)
      InstructionReferences.unknown_braces(node.instructions).map do |braces|
        issue(node, "warning", "unknown_braces", "instructions",
              "#{quote(node)} contains #{braces}, which reaches the agent as written: nothing replaces it.",
              nil, token: braces)
      end
    end

    # ---- specs ---------------------------------------------------------------

    def spec_issues(node)
      SPEC_FIELDS.flat_map do |list, (field, kind)|
        node.public_send(list).filter_map do |spec|
          severity = spec.required? ? "error" : "warning"
          if spec.blank?
            issue(node, "warning", "spec_name_invalid", field, "#{quote(node)} has an #{kind} with no name; it is ignored.")
          elsif (problem = spec.name_problem)
            issue(node, severity, "spec_name_invalid", field,
                  "#{quote(node)}: #{kind} #{spec.name} #{problem}. Use the file's name, or its path under /workspace/outputs.")
          elsif spec.name_pattern_invalid?
            issue(node, severity, "name_pattern_invalid", field,
                  "#{quote(node)}: #{kind} pattern #{spec.name_pattern} is not a valid regular expression. " \
                  "To match several files, write a glob such as reports/*.md in the name instead.")
          end
        end
      end
    end

    def input_issues(node, upstream)
      node.inputs.filter_map do |spec|
        next unless spec.required? && spec.name && spec.name_problem.nil?
        next if satisfied_by_asset?(node, spec) || satisfied_by_output?(spec, upstream)

        if @run_input_asset_ids && upstream.empty?
          issue(node, "error", "input_unsatisfied", "inputAssetSpecs",
                "#{quote(node)} requires #{spec.name}, but no earlier session, attached asset or file picked for this run provides it.")
        else
          issue(node, "warning", "input_unsatisfied", "inputAssetSpecs",
                "#{quote(node)} requires #{spec.name}, but no earlier session declares it as an output and no attached " \
                "asset has that name. An earlier session must write it, or it must be picked when the run starts.")
        end
      end
    end

    def satisfied_by_asset?(node, spec)
      available_asset_ids(node).any? do |id|
        asset = assets[id]
        asset && (spec.matches?(asset.name) || spec.matches?(asset.picker_name))
      end
    end

    def satisfied_by_output?(spec, upstream)
      upstream.any? do |key|
        @by_key[key]&.outputs&.any? do |output|
          (output.plain? && spec.matches?(output.name)) || (!output.plain? && spec.plain? && output.matches?(spec.name))
        end
      end
    end

    def collision_issues(node, upstream)
      producers = Hash.new { |hash, name| hash[name] = [] }
      upstream.each do |key|
        @by_key[key]&.outputs&.select(&:plain?)&.each { |spec| producers[spec.name] << @by_key[key] }
      end
      producers.select { |_, nodes| nodes.uniq.size > 1 }.map do |name, nodes|
        nodes = nodes.uniq
        issue(node, "warning", "output_collision", "outputAssetSpecs",
              "#{quote(node)} runs after #{nodes.map { |n| quote(n) }.to_sentence}, which all write #{name}; " \
              "it gets the copy from #{quote(nodes.first)}.")
      end
    end

    # ---- lookups -------------------------------------------------------------

    def available_asset_ids(node)
      (@base_asset_ids + node.asset_ids + @run_input_asset_ids.to_a).uniq
    end

    def available_server_ids(node)
      inherited = @inherit_all && @project ? @project.mcp_servers.pluck(:id) : []
      (@base_mcp_server_ids + node.mcp_server_ids + inherited).uniq
    end

    def assets
      @assets ||= begin
        ids = @nodes.flat_map { |node| InstructionReferences.ids(node.instructions, "asset") + node.asset_ids }
        ids += @base_asset_ids + @run_input_asset_ids.to_a
        @project ? Asset.accessible_from_project(@project).where(id: ids.uniq).index_by(&:id) : {}
      end
    end

    def servers
      @servers ||= begin
        ids = @nodes.flat_map { |node| InstructionReferences.ids(node.instructions, "mcp") }
        @project ? MCPServer.visible_for_project(@project).where(id: ids.uniq).index_by(&:id) : {}
      end
    end

    def quote(node) = %("#{node.name}")

    def issue(node, severity, code, field, message, ref = nil, token: nil, fix: nil)
      Issue.new(severity: severity, code: code, step_key: node.key, field: field, message: message,
                token: token || ref&.text, fix: fix)
    end
  end
end
