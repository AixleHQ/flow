# frozen_string_literal: true

module RuboCop
  module Cop
    module Tenant
      # Bans resolving a tenant-owned record by id through the model class in the
      # agent- and person-facing tool layers (app/services/internal_tools,
      # app/services/personal_tools).
      #
      # Every id those tools receive was typed by an agent or a person, and a bare
      # `Model.find(id)`, `find_by(id:)`, `where(id:)` or `exists?(id)` resolves it
      # across every company. Resolve through the caller's tenant instead — `writable_projects`,
      # `scoped_workflows`, `TenantScope.owned(Model, project:)`, or an association
      # of a record already resolved that way — so a foreign id is simply not found.
      class ScopedToolLookup < Base
        MSG = "Resolve `%<model>s` by id through the caller's tenant (TenantScope.owned, the tool's " \
              "scoped helpers, or an association), not across every company."

        TENANT_MODELS = %i[
          Agent Asset BoardColumn BoardTask ConfigItem Folder Gate Integration MCPServer Project
          Repository Skill Step StepRun SubStep TerminalSession Tool ToolResult TriggerBinding
          Workflow WorkflowRun
        ].freeze

        def_node_matcher :class_lookup, <<~PATTERN
          (send (const {nil? cbase} $_) ${:find :find_by :find_by! :where :exists?} $...)
        PATTERN

        def on_send(node)
          class_lookup(node) do |model, method, args|
            next unless TENANT_MODELS.include?(model)
            next unless by_id?(method, args)

            add_offense(node, message: format(MSG, model: model))
          end
        end

        private

        def by_id?(method, args)
          case method
          when :find then true
          when :exists? then args.any? { |arg| !arg.hash_type? } || keyed_by_id?(args)
          else keyed_by_id?(args)
          end
        end

        def keyed_by_id?(args)
          args.any? do |arg|
            arg.hash_type? && arg.pairs.any? { |pair| pair.key.sym_type? && pair.key.value == :id }
          end
        end
      end
    end
  end
end
