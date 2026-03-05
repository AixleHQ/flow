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
        - NEVER stop mid-task saying you need more information
        - Make reasonable assumptions when details are missing and document them
        - If a task is ambiguous, choose the most sensible interpretation and proceed

        **How to operate:**
        1. Analyze the prompt and all available context (MCP tools, project files, skills)
        2. Break the task into concrete steps
        3. Execute each step fully — write files, create artifacts, run commands
        4. Save all results to `/workspace/outputs/` so they persist after the session
        5. At the end, write a summary of what was done and any assumptions made

        Your output MUST be actionable artifacts (documents, code, configs), not a conversation.

        ### Session Completion (MANDATORY)

        You MUST call one of these tools when finished:
        - **finish_session** — when the task is **fully completed** successfully. Optional `note` parameter.
        - **fail_session** — when the task **cannot be completed**. Required `reason`, optional `note`.

        Call `finish_session` ONLY when ALL deliverables are produced.
        Call `fail_session` if ANY of these are true:
        - A required resource is missing (repository, file, API, tool)
        - You cannot produce the expected deliverables
        - A critical error prevents completing the task

        **You MUST call one of these tools to end the session — it will not end on its own.**
      RULES
    end

    def language_rule
      "**Communication Language:** #{preferred_language} — ALL communication with the user MUST be in this language."
    end

    def preferred_language
      session.user&.preferred_agent_language
    end
  end
end
