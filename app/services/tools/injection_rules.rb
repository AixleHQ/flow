# frozen_string_literal: true

module Tools
  # Named session predicates for the plumbing tools that stay automatic in
  # TerminalSession#available_tools. Closed vocabulary: the DSL rejects
  # unknown rule names at class-load time.
  module InjectionRules
    # Plumbing only (docs/design/tool-attachment.md §2.1). Every other tool is
    # served when a workflow, a step or the session itself attached it.
    RULES = {
      # finish_session, fail_session, list_sub_steps, mark_sub_step — how a
      # session ends and reports progress. Served to every session.
      any_session: ->(_ctx) { true },
      # read_tool_result — the only way to poll the result of a container tool
      # the session attached.
      container_tools_present: ->(ctx) { ctx.candidate_tools.any? { |t| t.execution_mode.container? } },
      # get_config_item — served only where an attachment already authorized it.
      # Resolved through SessionConfigResolver so a workflow step sees the items
      # its workflow/step named, not just the (empty) session association.
      config_items_attached: lambda { |ctx|
        ctx.session.present? && SessionConfigResolver.new(ctx.session).resolve_config_item_ids.any?
      }
    }.freeze

    def self.fetch(rule)
      RULES.fetch(rule.to_sym)
    end
  end
end
