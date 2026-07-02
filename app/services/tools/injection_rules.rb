# frozen_string_literal: true

module Tools
  # Named session predicates that replace the kind-driven auto-injection in
  # TerminalSession#available_tools. Closed vocabulary: the DSL rejects
  # unknown rule names at class-load time.
  module InjectionRules
    RULES = {
      # kind :workflow — board_*, list_sub_steps, mark_sub_step, slack_post_message
      workflow_step_session: ->(ctx) { ctx.session_type == "workflow_step" },
      # kind :internal — read_tool_result, needed to poll async container tools
      container_tools_present: ->(ctx) { ctx.candidate_tools.any? { |t| t.execution_mode.container? } },
      # kind :internal — finish_session/fail_session lifecycle tools
      non_interactive_session: ->(ctx) { ctx.mode == "non_interactive" }
    }.freeze

    def self.fetch(rule)
      RULES.fetch(rule.to_sym)
    end
  end
end
