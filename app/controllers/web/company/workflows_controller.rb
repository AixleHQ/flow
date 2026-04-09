# frozen_string_literal: true

class Web::Company::WorkflowsController < Web::Company::ApplicationController
  def index
    workflows = Workflow.visible_for_company(current_company)
                        .includes(:steps, :runs)
                        .order(:name)

    render inertia: "Company/Workflows/Index", props: {
      workflows: workflows.map { |w| WorkflowResource.new(w).to_h }
    }
  end

  def builder
    workflow = Workflow.for_company(current_company)
                      .includes(steps: :sub_steps)
                      .find(params[:id])

    render inertia: "Projects/Workflows/BuilderPage", props: {
      project: nil,
      workflow: WorkflowResource.new(workflow).to_h,
      steps: workflow.steps.not_deleted.map { |s| StepResource.new(s).to_h },
      read_only: false,
      configured_agents: current_user.configured_agents,
      agents: InertiaRails.defer(group: "resources") {
        Agent.for_company(current_company).map { |r| PickerResource.new(r).to_h }
      },
      tools: InertiaRails.defer(group: "resources") {
        Tool.for_company(current_company).map { |r| PickerResource.new(r).to_h }
      },
      skills: InertiaRails.defer(group: "resources") {
        Skill.for_company(current_company).map { |r| PickerResource.new(r).to_h }
      },
      mcp_servers: InertiaRails.defer(group: "resources") {
        MCPServer.for_company(current_company).map { |r| PickerResource.new(r).to_h }
      },
      assets: InertiaRails.defer(group: "resources") {
        current_company.assets.active.map { |r| PickerResource.new(r).to_h }
      },
      repositories: InertiaRails.defer(group: "resources") {
        Repository.visible_for_company(current_company).map { |r| PickerResource.new(r).to_h }
      },
      agent_models: InertiaRails.defer(group: "resources") {
        current_user.agent_models_for_props
      }
    }
  end

  def create
    workflow = current_company.workflows.new(workflow_params)
    workflow.scope = current_company

    if workflow.save
      redirect_to company_workflows_path, notice: "Workflow created"
    else
      redirect_to company_workflows_path, alert: workflow.errors.full_messages.join(", ")
    end
  end

  def destroy
    workflow = current_company.workflows.find(params[:id])
    workflow.destroy
    redirect_to company_workflows_path, notice: "Workflow deleted"
  end

  private

  def workflow_params
    params.require(:workflow).permit(:name, :description, config: {})
  end
end
