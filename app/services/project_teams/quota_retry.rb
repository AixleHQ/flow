# frozen_string_literal: true

module ProjectTeams
  # A step of a team's run stopped on its owner's quota and is set to retry: the
  # retry goes to the next member the team's strategy picks. The run changes
  # owner from here on — the retried step and every later step are created for
  # the new member (SessionService builds a step's session for workflow_run.user);
  # earlier steps keep theirs. docs/design/project-teams.md, "Retry on quota".
  module QuotaRetry
    AUDIT_ACTION = "run_owner_reassigned"

    module_function

    # @return [Boolean] whether the run now belongs to another member
    def reassign!(run, step_run:)
      return false if run.team.nil?

      pick = Picker.call(team: run.team, workflow: run.workflow, agent_runtime: run.agent_runtime,
                         exclude_user_ids: [ run.user_id ])
      unless pick.picked?
        step_run&.update!(error_message: [ step_run.error_message, pick.message ].compact_blank.join("\n\n"))
        return false
      end

      previous = run.user
      run.transaction do
        run.update!(user: pick.user)
        audit!(run, previous, pick.user, step_run)
      end
      true
    end

    def audit!(run, from, to, step_run)
      Audit.create!(
        auditable: run, associated: run.project, action: AUDIT_ACTION,
        audited_changes: { "user_id" => [ from&.id, to.id ] },
        comment: "Run #{run.id} moved from #{from&.name || 'nobody'} to #{to.name} of team " \
                 "\"#{run.team.name}\" after a quota stop on step run #{step_run&.id}"
      )
    end
  end
end
