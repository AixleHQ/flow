# frozen_string_literal: true

module ContextBuilders
  class CriticalRules < Base
    def build
      rules = []
      rules << non_interactive_rules if session.mode == "non_interactive"
      rules << language_rule if preferred_language.present?

      return [] if rules.compact.empty?

      [ section(
        tag: "critical-rules",
        priority: :critical,
        content: rules.compact.join("\n\n"),
        position_hint: :top
      ) ]
    end

    private

    def non_interactive_rules
      <<~RULES.strip
        ## CRITICAL: Non-Interactive Mode

        This session runs **non-interactively** — there is NO human to respond.
        The user's prompt is the ONLY input you will receive. No follow-up is possible.

        **Strict rules:**
        - NEVER ask questions, request clarifications, or wait for input
        - NEVER present options and ask the user to choose
        - Make only minor, reversible assumptions when details are missing, and document them
        - Consult available sources before deciding that an essential requirement is missing
        - If an essential requirement cannot be verified, or an unresolved conflict prevents completion,
          record the blocker and call `fail_session`; do not invent a decision or report partial work as success

        **How to operate:**
        1. Analyze the prompt and all available context (MCP tools, project files, skills)
        2. Break the task into concrete steps
        3. Execute each step fully — write files, create artifacts, run commands
        4. At the end, write a summary of what was done and any assumptions made

        Your output MUST be actionable artifacts (documents, code, configs), not a conversation.

        ### Session Completion (MANDATORY)

        The session ends ONLY when you call `finish_session` (objective fully met) or
        `fail_session` (objective cannot be met). It will NOT end on its own, and
        ending your turn without one of those calls leaves it hanging until a sweeper
        kills it. The full rule — including when partial work must be `fail_session` —
        is in the `<session-completion>` section at the very end of this context.
      RULES
    end

    def language_rule
      "**Communication Language:** #{preferred_language} — ALL communication with the user MUST be in this language."
    end

    def preferred_language
      SessionCompany.membership_for(session)&.preferred_agent_language
    end
  end
end
