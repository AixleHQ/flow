# frozen_string_literal: true

module Runners
  # Whether a person, or a client of the API, may choose `runner_id` on a
  # workflow, a run or a session (docs/design/agent-runtimes/DESIGN.md §3.2,
  # §11). A company without the flag has the field refused, null included: a
  # null pick on a run is a hosted override, and without the flag nothing may
  # move a run off its workflow's runner. The one exception is clearing a
  # workflow's own runner (#workflow_error). A pick names a runner the project can
  # see and that is not deleted; a disabled or revoked one can be picked, and the
  # launch then fails with its name (§3.4).
  #
  #   Runners::Selection.error(params[:runner_id], project: project)  # => nil, or the message
  module Selection
    NOT_ENABLED = "External runners are not enabled for this company."

    module_function

    def error(runner_id, project:, interactive: false)
      return NOT_ENABLED unless Feature.enabled?(:external_runners, company: project.company)
      return if runner_id.blank?

      runner = Runner.visible_for_project(project).find_by(id: runner_id)
      return "Runner #{runner_id} is not available to project #{project.name}." if runner.nil?

      # §8: no runner has `interactive_terminal` until the tunnel (§15 task 16).
      "Runner \"#{runner.name}\" can't run interactive sessions yet." if interactive
    end

    # A workflow's runner is checked only when it changes, so a workflow saved
    # with a runner that went away since (or restored with one) stays editable.
    # Switching a workflow back to hosted is allowed without the flag: it is the
    # way out for a company whose flag was turned off while its workflows still
    # name a runner (§11). Unlike a hosted pick on a run, it moves nothing off
    # the workflow's runner behind the person's back.
    def workflow_error(workflow, runner_id)
      return if runner_id.presence&.to_i == workflow.runner_id
      return if runner_id.blank?

      project = workflow.runner_project
      return "A system workflow runs hosted only." if project.nil?

      error(runner_id, project: project)
    end
  end
end
