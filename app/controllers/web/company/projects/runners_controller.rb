# frozen_string_literal: true

# A project's runners page: the project's own runners and the company's
# (Runner.visible_for_project). Only the project's own are managed here
# (docs/design/agent-runtimes/DESIGN.md §3.2).
#
# The policy authorizes the action (`dynamic_authorize!`), and the lookup
# decides which runner a request may touch: index and show find it among the
# visible runners, and every write among the project's own, so a company runner
# is not found by a write from this page.
class Web::Company::Projects::RunnersController < Web::Company::Projects::ApplicationController
  include RunnerRegistrationTokens
  include RunnerMachinesList
  include RunnerMachineReturn

  requires_feature :external_runners

  def index
    render inertia: "Projects/Runners/RunnersPage", props: {
      runners: visible_runners.includes(:created_by).order(:name).map { |runner| RunnerResource.new(runner).to_h },
      runner_types: Runners::Form.runner_types,
      can_manage: runners_policy.create?
    }
  end

  def show
    runner = visible_runners.find(params[:id])

    render inertia: "Projects/Runners/RunnerPage", props: {
      runner: RunnerResource.new(runner).to_h,
      machines: machines_prop(runner),
      runner_types: Runners::Form.runner_types,
      can_manage: runners_policy.update? && runner.project_id == current_project.id
    }
  end

  def create
    runner = current_project.runners.new(company: current_project.company, created_by: current_user)
    runner.assign_attributes(Runners::Form.attributes(params, creating: true))

    if Runners::Save.call(runner)
      redirect_to company_project_runner_path(current_project, runner), notice: "Runner created"
    else
      redirect_to company_project_runners_path(current_project), inertia: { errors: runner.errors }
    end
  end

  def update
    runner = own_runners.find(params[:id])
    runner.assign_attributes(Runners::Form.attributes(params, creating: false))

    if Runners::Save.call(runner)
      redirect_to company_project_runner_path(current_project, runner), notice: "Runner updated"
    else
      redirect_to company_project_runner_path(current_project, runner), inertia: { errors: runner.errors }
    end
  end

  # A soft delete that revokes in the same write (§2.5): workflows and past
  # sessions can still name the runner they used.
  def destroy
    own_runners.find(params[:id]).soft_delete!
    redirect_to company_project_runners_path(current_project), notice: "Runner deleted"
  end

  # "Add machine": a single-use registration token for a `manual` runner of
  # the project, returned once (DESIGN.md §6.3). A company runner is not found.
  def registration_token
    render_registration_token(own_runners.find(params[:id]))
  end

  # Return to service for a `failed` machine of a `manual` runner of the
  # project (§5.2, §7.2). A company runner is not found.
  def return_to_service
    runner = own_runners.find(params[:id])
    redirect_to company_project_runner_path(current_project, runner), **return_machine_to_service(runner)
  end

  def disable = transition(:disable, "disabled")
  def enable = transition(:enable, "enabled")
  def revoke = transition(:revoke, "revoked")

  private

  def transition(event, done)
    runner = own_runners.find(params[:id])

    unless runner.public_send(:"may_#{event}?")
      return redirect_to company_project_runner_path(current_project, runner),
                         alert: "A #{runner.status} runner cannot be #{done}"
    end

    runner.public_send(:"#{event}!")
    redirect_to company_project_runner_path(current_project, runner), notice: "Runner #{done}"
  end

  # What the page lists and shows: the project's own and the company's.
  def visible_runners
    Runner.visible_for_project(current_project)
  end

  # What the page manages: the project's own only.
  def own_runners
    current_project.runners.not_deleted
  end

  def runners_policy
    Web::Company::Projects::RunnersPolicy.new(policy_context, :runners)
  end
end
