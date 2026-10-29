# frozen_string_literal: true

# The actions the company and project runners controllers share
# (docs/design/agent-runtimes/DESIGN.md §3.2, §15 task 2). Each includer names
# its scope: where runners are listed and found, the runner a create builds,
# its policy, its pages and its paths.
#
# Each includer declares `requires_feature :external_runners` itself, so the
# flag the controller needs is read where the controller is.
module RunnerManagement
  extend ActiveSupport::Concern

  def index
    runners = listed_runners.includes(:created_by).order(:name)

    render inertia: "#{page_prefix}/RunnersPage", props: {
      runners: runners.map { |runner| RunnerResource.new(runner).to_h },
      runner_types: runner_types_props,
      can_manage: runner_policy(:runners).create?
    }
  end

  def show
    runner = find_runner

    render inertia: "#{page_prefix}/RunnerPage", props: {
      runner: RunnerResource.new(runner).to_h,
      runner_types: runner_types_props,
      can_manage: runner_policy(runner).update?,
      workflows_using: workflows_using(runner)
    }
  end

  def create
    runner = build_runner
    runner.assign_attributes(runner_params(creating: true))
    authorize_runner!(runner, :create?)

    if Runners::Save.call(runner)
      redirect_to runner_page_path(runner), notice: "Runner created"
    else
      redirect_to runners_page_path, inertia: { errors: runner.errors }
    end
  end

  def update
    runner = find_runner
    authorize_runner!(runner, :update?)
    runner.assign_attributes(runner_params(creating: false))

    if Runners::Save.call(runner)
      redirect_to runner_page_path(runner), notice: "Runner updated"
    else
      redirect_to runner_page_path(runner), inertia: { errors: runner.errors }
    end
  end

  # A soft delete that revokes in the same write (§2.5): workflows and past
  # sessions can still name the runner they used.
  def destroy
    runner = find_runner
    authorize_runner!(runner, :destroy?)
    runner.soft_delete!
    redirect_to runners_page_path, notice: "Runner deleted"
  end

  def disable = transition(:disable, "disabled")
  def enable = transition(:enable, "enabled")
  def revoke = transition(:revoke, "revoked")

  private

  def transition(event, done)
    runner = find_runner
    authorize_runner!(runner, :"#{event}?")

    unless runner.public_send(:"may_#{event}?")
      return redirect_to runner_page_path(runner), alert: "A #{runner.status} runner cannot be #{done}"
    end

    runner.public_send(:"#{event}!")
    redirect_to runner_page_path(runner), notice: "Runner #{done}"
  end

  def find_runner
    listed_runners.find(params[:id])
  end

  # The workflows that name the runner (§11), the ones this page may show:
  # deleting the runner asks for confirmation and lists them (§3.4).
  def workflows_using(runner)
    Workflow.active.where(runner_id: runner.id, project_id: workflow_projects.select(:id))
            .includes(:scope).order(:name).map do |workflow|
      { id: workflow.id, name: workflow.name, project_id: workflow.project_id, project_name: workflow.scope.name }
    end
  end

  # The record-level half of the policy: the action was authorized for the
  # role before the lookup, and this decides whether this runner is the
  # user's to change from this page.
  def authorize_runner!(runner, query)
    raise Pundit::NotAuthorizedError unless runner_policy(runner).public_send(query)
  end

  def runner_policy(record) = runner_policy_class.new(policy_context, record)

  # Scope, company and author come from the request, never from params. The
  # type, `runner_type` as in the model and RunnerResource, is chosen once, at
  # creation.
  def runner_params(creating:)
    runner = params.require(:runner)
    attributes = runner.permit(:name, :max_concurrency, :max_environments, :reuse_policy, :integration_id)
    attributes[:runner_type] = runner[:runner_type] if creating
    attributes[:config] = config_param(runner[:config]) if runner.key?(:config)
    attributes
  end

  # Validated whole by Runners::ConfigSchema, which refuses any key it does not
  # declare, so it is taken as sent rather than through a permit list that
  # would have to repeat the schema.
  def config_param(value)
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
  end

  def runner_types_props
    Runners::Adapter.available_types.map do |runner_type|
      adapter = Runners::Adapter.for_type(runner_type)
      # The schema's property names are config keys, sent back by the form as
      # they are, so they are not camelized.
      {
        runner_type: runner_type,
        config_schema: DeepKeyCamelizer.verbatim(adapter.config_schema),
        capabilities: adapter.capabilities(Runner.new(runner_type: runner_type)).to_h,
        DeepKeyCamelizer::PRESERVE_MARKER => [ "configSchema" ]
      }
    end
  end
end
