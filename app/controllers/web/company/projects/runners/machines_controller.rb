# frozen_string_literal: true

# A machine of a project's own runner (docs/design/agent-runtimes/DESIGN.md
# §3.2). The policy authorizes the action; the runner is found among the
# project's own, so a company runner is not found, and the machine among that
# runner's own.
class Web::Company::Projects::Runners::MachinesController < Web::Company::Projects::ApplicationController
  include RunnerMachineReturn

  requires_feature :external_runners

  # Revoke for a machine of a `manual` runner of the project (§9.3).
  def revoke
    runner = current_project.runners.not_deleted.find(params[:runner_id])
    redirect_to company_project_runner_path(current_project, runner), **revoke_machine(runner)
  end
end
