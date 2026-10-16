# frozen_string_literal: true

module ContextBuilders
  class OutputRules < Base
    # The builder's deliverable is configuration made through its tools, not files.
    def applicable?
      !session.aixle_builder?
    end

    def build
      [ section(
        tag: "output-rules",
        priority: :critical,
        content: build_output_rules,
        position_hint: :bottom
      ) ]
    end

    private

    def build_output_rules
      lines = [ "## Output Rules" ]
      lines << ""
      lines << "- Files in `/workspace/assets/` are READ-ONLY — copy to outputs before editing"
      lines << "- Use only the MCP servers and tools needed for the task"
      lines << "- Write clean, production-quality code following project conventions"

      if session.mode == "non_interactive"
        lines << "- When done, you MUST call `finish_session` (success) or `fail_session` (failure) to end the session"
        lines << "- **If you could not fully accomplish the objective, call `fail_session` — do NOT call `finish_session` for partial or failed work**"
      end

      lines.join("\n")
    end
  end
end
