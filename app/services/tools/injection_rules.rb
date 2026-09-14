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
      non_interactive_session: ->(ctx) { ctx.mode == "non_interactive" },
      # coder_* tools — surface through aixle-tools whenever the project has an
      # active Coder integration (mirrors how slack_post_message is gated).
      coder_integration_connected: ->(ctx) { ctx.connected?(:coder) },
      # refresh_github_token — only sessions holding a GitHub clone carry the
      # one-hour installation token that can expire mid-run.
      github_repositories_attached: lambda { |ctx|
        ctx.session.present? &&
          ctx.session.repositories.includes(:integration).any? { |repo| repo.integration&.github? }
      },
      # azure_devops_* repository tools — every one of them takes a
      # `repository_id` that must already be attached to the session, so there
      # is nothing for them to act on without one. They are not offered in the
      # picker at all (TagCatalog marks the tag hidden and the tools are not
      # user_attachable): attaching an Azure repository IS the opt-in.
      azure_repositories_attached: lambda { |ctx|
        ctx.session.present? &&
          ctx.session.repositories.includes(:integration).any? { |repo| repo.integration&.azure_devops? }
      },
      # azure_devops_* work item and build tools, plus list_connections. These
      # are scoped by `integration_id` rather than by a repository, so the
      # connection is the only thing they need — a project running Azure Boards
      # against repositories hosted elsewhere still reaches them. Mirrors the
      # Coder gating exactly.
      azure_integration_connected: ->(ctx) { ctx.connected?(:azure_devops) },
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
