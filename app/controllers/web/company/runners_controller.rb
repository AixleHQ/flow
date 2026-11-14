# frozen_string_literal: true

# Company runners, a tab of company settings: visible to every project of the
# company, managed by a company admin (docs/design/agent-runtimes/DESIGN.md §3.2).
#
# The policy authorizes the action (`dynamic_authorize!`), and the lookup
# decides which runner a request may touch: the company-level runners only, so
# a project's runner is not found here.
class Web::Company::RunnersController < Web::Company::ApplicationController
  include RunnerRegistrationTokens
  include RunnerMachinesList

  requires_feature :external_runners

  def index
    render inertia: "Company/Settings/RunnersPage", props: {
      runners: runners_prop(company_runners.includes(:created_by).order(:name).to_a),
      runner_types: Runners::Form.runner_types,
      can_manage: runners_policy.create?
    }
  end

  def show
    runner = company_runners.find(params[:id])

    render inertia: "Company/Settings/RunnerPage", props: {
      runner: RunnerResource.new(runner).to_h,
      machines: machines_prop(runner),
      runner_types: Runners::Form.runner_types,
      can_manage: runners_policy.update?
    }
  end

  def create
    runner = current_company.runners.new(project: nil, created_by: current_user)
    runner.assign_attributes(Runners::Form.attributes(params, creating: true))

    if Runners::Save.call(runner)
      redirect_to company_settings_runner_path(runner), notice: "Runner created"
    else
      redirect_to company_settings_runners_path, inertia: { errors: runner.errors }
    end
  end

  def update
    runner = company_runners.find(params[:id])
    runner.assign_attributes(Runners::Form.attributes(params, creating: false))

    if Runners::Save.call(runner)
      redirect_to company_settings_runner_path(runner), notice: "Runner updated"
    else
      redirect_to company_settings_runner_path(runner), inertia: { errors: runner.errors }
    end
  end

  # A soft delete that revokes in the same write (§2.5): workflows and past
  # sessions can still name the runner they used.
  def destroy
    company_runners.find(params[:id]).soft_delete!
    redirect_to company_settings_runners_path, notice: "Runner deleted"
  end

  # "Add machine": a single-use registration token for a `manual` runner,
  # returned once (DESIGN.md §6.3).
  def registration_token
    render_registration_token(company_runners.find(params[:id]))
  end

  def disable = transition(:disable, "disabled")
  def enable = transition(:enable, "enabled")
  def revoke = transition(:revoke, "revoked")

  private

  def transition(event, done)
    runner = company_runners.find(params[:id])

    unless runner.public_send(:"may_#{event}?")
      return redirect_to company_settings_runner_path(runner), alert: "A #{runner.status} runner cannot be #{done}"
    end

    runner.public_send(:"#{event}!")
    redirect_to company_settings_runner_path(runner), notice: "Runner #{done}"
  end

  # This page's own runners, which are all it lists and all it manages.
  def company_runners
    current_company.runners.not_deleted.company_level
  end

  def runners_policy
    Web::Company::RunnersPolicy.new(policy_context, :runners)
  end
end
