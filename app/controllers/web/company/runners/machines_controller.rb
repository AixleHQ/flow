# frozen_string_literal: true

# A machine of a company runner (docs/design/agent-runtimes/DESIGN.md §3.2).
# The policy authorizes the action; the runner is found among the company-level
# runners, and the machine among that runner's own.
class Web::Company::Runners::MachinesController < Web::Company::ApplicationController
  include RunnerMachineReturn

  # Return to service for a `failed` machine of a `manual` runner (§5.2, §7.2).
  def return_to_service
    runner = company_runners.find(params[:settings_runner_id])
    redirect_to company_settings_runner_path(runner), **return_machine_to_service(runner)
  end

  private

  def company_runners
    current_company.runners.not_deleted.where(project_id: nil)
  end
end
