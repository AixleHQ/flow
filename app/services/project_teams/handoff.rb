# frozen_string_literal: true

module ProjectTeams
  # A step of a team's run stopped on its owner's quota or login: the run goes to
  # the next member the team's strategy picks, and the step runs again as them.
  # The run changes owner from here on — the retried step and every later step are
  # created for the new member (SessionService builds a step's session for
  # workflow_run.user); earlier steps keep theirs. docs/design/project-teams.md,
  # "Handing a run on".
  module Handoff
    AUDIT_ACTION = "run_owner_reassigned"

    STOPS = { "quota_exceeded" => "a quota stop", "auth_expired" => "a login failure" }.freeze

    module_function

    # @return [Boolean] whether the run now belongs to another member
    def reassign!(run, step_run:)
      return false if run.team.nil?

      pick = Picker.call(team: run.team, workflow: run.workflow, agent_runtime: run.agent_runtime,
                         exclude_user_ids: [ run.user_id, *previous_owner_ids(run) ])
      unless pick.picked?
        step_run&.update!(error_message: [ step_run.error_message, pick.message ].compact_blank.join("\n\n"))
        return false
      end

      previous = run.user
      run.transaction do
        # The stop is behind the run now; left in place it would read as why a run
        # that then completes, or fails on something else, ended.
        run.update!(user: pick.user, failure_reason: nil, failed_agent_credential_id: nil)
        audit!(run, previous, pick.user, step_run)
      end
      true
    end

    # Everyone the run has already left: a login that failed puts no hold on the
    # credential, so without this two members whose logins both fail would hand
    # the run back and forth for good.
    def previous_owner_ids(run)
      Audit.where(auditable: run, action: AUDIT_ACTION).map { |audit| Array(audit.audited_changes["user_id"]).first }
    end

    def audit!(run, from, to, step_run)
      Audit.create!(
        auditable: run, associated: run.project, action: AUDIT_ACTION,
        audited_changes: { "user_id" => [ from&.id, to.id ] },
        comment: "Run #{run.id} moved from #{from&.name || 'nobody'} to #{to.name} of team " \
                 "\"#{run.team.name}\" after #{STOPS.fetch(step_run&.error_category.to_s, 'a stop')} " \
                 "on step run #{step_run&.id}"
      )
    end
  end
end
