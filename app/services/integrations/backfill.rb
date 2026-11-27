# frozen_string_literal: true

module Integrations
  # Gives the workflows and the sessions that exist the integrations they get today
  # (docs/design/session-integrations.md §7), so the gates that read a session's integration set
  # take nothing away from them. Idempotent: what is already linked is not added again.
  #
  # The data migration BackfillSessionIntegrations follows the same rules in its own SQL.
  class Backfill
    # Per workflow, what Integrations::Defaults names for its project.
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    # → the number of links added
    def workflows
      added = 0
      Workflow.where(scope_type: "Project").includes(:scope).find_each do |workflow|
        project = workflow.scope
        next if project.nil?

        wanted = project_integration_ids(project) - workflow.base_integration_ids
        added += attach(workflow, wanted)
      end
      added
    end

    # The sessions that can still be used: not ended, and suspended (a restore copies the set).
    # A session that already has a set is left alone. → the number of rows added
    def sessions(since: nil)
      scope = TerminalSession.not_ended.or(TerminalSession.suspended)
      scope = scope.where(created_at: since..) if since
      added = 0
      scope.where.not(id: attached_session_ids).includes(:project).find_each do |session|
        ids = session_integration_ids(session)
        next if ids.empty?

        owned = TenantScope.owned(Integration, project: session.project, company: SessionCompany.company_for(session)).where(id: ids)
        session.integrations = owned
        added += owned.size
      end
      added
    end

    def project_integration_ids(project) = Defaults.ids(project, logger: @logger)

    private

    def attached_session_ids
      TerminalSession.joins("INNER JOIN session_integrations ON session_integrations.terminal_session_id = terminal_sessions.id")
                     .select(:id)
    end

    def session_integration_ids(session)
      resolver = SessionConfigResolver.new(session)
      ids = resolver.resolve_integration_ids
      ids += project_integration_ids(session.project) if session.project && !session.workflow_step?
      ids.uniq
    end

    def attach(workflow, integration_ids)
      return 0 if integration_ids.empty?

      position = WorkflowResourceLink.where(workflow_id: workflow.id).maximum(:position).to_i
      rows = integration_ids.each_with_index.map do |id, index|
        { workflow_id: workflow.id, integration_id: id, position: position + index + 1 }
      end
      WorkflowResourceLink.insert_all(rows)
      rows.size
    end
  end
end
