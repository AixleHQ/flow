# frozen_string_literal: true

module InternalTools
  module Concerns
    # CoderResolver — pull the Coder integration this tool call is routed to.
    #
    # Coder tools surface through the internal aixle-tools MCP server (gated on
    # `requires_integration :coder`), exactly like the Slack tools. The
    # integration is resolved directly from the session's project: the
    # project-scoped Coder integration if present, otherwise the company-wide
    # one. This mirrors SlackPostMessage#slack_integration.
    module CoderResolver
      class NotConfiguredError < StandardError; end

      def coder_integration
        @coder_integration ||= resolve_coder_integration
      end

      def require_coder!
        return if coder_integration

        raise NotConfiguredError,
              "No active Coder integration for this project. " \
              "Connect it in Project Settings → Integrations."
      end

      private

      def resolve_coder_integration
        return nil if project.nil?

        Integration.active
                   .where(provider: :coder, company_id: project.company_id)
                   .where("project_id = :pid OR project_id IS NULL", pid: project.id)
                   .order(Arel.sql("project_id IS NULL")) # prefer project-scoped over company-wide
                   .first
      end
    end
  end
end
