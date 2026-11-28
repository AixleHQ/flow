# frozen_string_literal: true

module InternalTools
  module Concerns
    # CoderResolver: the Coder integration a tool call acts through
    # (docs/design/session-integrations.md §5.3).
    #
    # The candidates are the Coder integrations in the session's own set, never the project's.
    # `integration_id` names one. It may be left out when the set holds exactly one Coder
    # integration, so a prompt that calls `coder_allocate_machine` with no arguments keeps
    # working; with two or more, leaving it out is an error that lists them.
    module CoderResolver
      class NotConfiguredError < StandardError; end

      INTEGRATION_ID_SCHEMA = {
        type: "integer",
        description: "The Coder integration to act through (the ID in this session's Available Integrations). " \
                     "Optional when exactly one Coder integration is attached to the session."
      }.freeze

      def coder_integration
        @coder_integration ||= resolve_coder_integration
      end

      def require_coder!
        coder_integration
        nil
      end

      private

      def resolve_coder_integration
        attached = session ? session.integrations.where(provider: :coder).order(:id).to_a : []
        if attached.empty?
          raise NotConfiguredError,
                "No Coder integration is attached to this session. Attach one to the workflow or the session, " \
                "or connect it in Project Settings → Integrations."
        end

        requested = params[:integration_id]
        integration = requested.present? ? named_coder_integration(attached, requested) : sole_coder_integration(attached)
        return integration if integration.active?

        raise NotConfiguredError, "Coder integration #{integration.id} (#{integration.name}) is #{integration.status}, " \
                                  "not active. Test the connection or replace its token in Project Settings → Integrations."
      end

      def named_coder_integration(attached, requested)
        id = Integer(requested.to_s, 10)
        attached.find { |integration| integration.id == id } ||
          raise(NotConfiguredError, "Coder integration #{requested} is not attached to this session. #{candidate_list(attached)}")
      rescue ArgumentError
        raise NotConfiguredError, "integration_id must be an integer. #{candidate_list(attached)}"
      end

      def sole_coder_integration(attached)
        return attached.first if attached.one?

        raise NotConfiguredError, "This session has several Coder integrations: pass `integration_id`. #{candidate_list(attached)}"
      end

      def candidate_list(attached)
        "Attached: " + attached.map { |i| "#{i.id} (#{i.name}#{", #{i.coder_host}" if i.coder_host.present?}, #{i.status})" }.join("; ") + "."
      end
    end
  end
end
