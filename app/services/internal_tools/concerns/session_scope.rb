# frozen_string_literal: true

module InternalTools
  module Concerns
    # SessionScope — which OTHER sessions the current session may look at.
    #
    # A session is not a person, so it cannot have its own access level. It
    # borrows its owner's: the same `readable_by` + `visible_to?` pair the web
    # UI and the personal MCP server apply, asked on behalf of the user the
    # session runs as. On top of that, the listing is pinned to the session's
    # own project — a supervising agent watches its neighbours, never the whole
    # company.
    #
    # Not-found rather than not-allowed, matching PersonalTools::Base — a
    # session its owner keeps private is indistinguishable from one that does
    # not exist.
    module SessionScope
      private

      def supervision_owner
        session&.user
      end

      def supervision_scope
        return TerminalSession.none if supervision_owner.nil? || session.project_id.blank?

        TerminalSession.readable_by(supervision_owner).where(project_id: session.project_id)
      end

      # `visible_to?` depends on the owner's per-phase sharing preferences and
      # cannot be expressed in SQL, so it filters loaded rows. Callers read a
      # bounded window first.
      def supervision_visible(records)
        owner = supervision_owner
        records.select { |record| record.visible_to?(owner) }
      end

      def find_supervised_session(id)
        record = supervision_scope.find_by(id: id)
        record if record&.visible_to?(supervision_owner)
      end
    end
  end
end
