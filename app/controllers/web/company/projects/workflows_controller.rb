# frozen_string_literal: true

class Web::Company::Projects::WorkflowsController < Web::Company::Projects::ApplicationController
  include Web::Company::WorkflowTemplateSourceLookup

  def index
    templates = WorkflowTemplate.visible_to(current_user, current_company)
                                .includes(:owner, :current_version)
                                .where.not(current_version_id: nil)
                                .order(:name)

    workflows = Workflow.visible_for_project(current_project)
                        .includes(:steps, :runs)
    render inertia: "Projects/Workflows/WorkflowsPage", props: {
      project: project_props,
      workflows: -> {
        workflows.map { |w|
          WorkflowResource.new(w).to_h.merge(
            steps: w.steps.not_deleted.map { |s| StepResource.new(s).to_h }
          )
        }
      },
      workflow_templates: -> { templates.map { |t| WorkflowTemplateResource.new(t).to_h } },
      published_templates_by_source: -> { published_templates_for_workflows(workflows) },
      configured_agents: current_user.configured_agents,
      assets: InertiaRails.defer(group: "resources") {
        current_project.assets.active.map { |r| PickerResource.new(r).to_h }
      },
      repositories: InertiaRails.defer(group: "resources") {
        Repository.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      agent_models: InertiaRails.defer(group: "resources") {
        current_user.agent_models_for_props
      }
    }
  end

  def builder
    workflow = Workflow.visible_for_project(current_project)
                      .includes(steps: :sub_steps)
                      .find(params[:id])

    render inertia: "Projects/Workflows/BuilderPage", props: {
      project: project_props,
      workflow: WorkflowResource.new(workflow).to_h,
      steps: workflow.steps.not_deleted.map { |s| StepResource.new(s).to_h },
      read_only: workflow.scope_type == "Company",
      configured_agents: current_user.configured_agents,
      agents: InertiaRails.defer(group: "resources") {
        Agent.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      tools: InertiaRails.defer(group: "resources") {
        Tool.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      skills: InertiaRails.defer(group: "resources") {
        Skill.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      mcp_servers: InertiaRails.defer(group: "resources") {
        MCPServer.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      assets: InertiaRails.defer(group: "resources") {
        current_project.assets.active.map { |r| PickerResource.new(r).to_h }
      },
      repositories: InertiaRails.defer(group: "resources") {
        Repository.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      agent_models: InertiaRails.defer(group: "resources") {
        current_user.agent_models_for_props
      }
    }
  end

  def create
    if params.dig(:workflow, :workflow_template_version_id).present?
      create_from_template!
    else
      workflow = current_project.workflows.new(workflow_params)
      if workflow.save
        redirect_to company_project_workflows_path(current_project), notice: "Workflow created"
      else
        redirect_to company_project_workflows_path(current_project), alert: workflow.errors.full_messages.join(", ")
      end
    end
  end

  def from_template
    create_from_template!
  end

  def duplicate
    source = Workflow.visible_for_project(current_project).find(params[:id])
    copy = WorkflowDuplicator.new(source, target_scope: current_project).duplicate!
    redirect_to builder_company_project_workflow_path(current_project, copy)
  rescue ActiveRecord::RecordNotFound
    redirect_to company_project_workflows_path(current_project), alert: "Workflow not found"
  end

  def update
    workflow = current_project.workflows.find(params[:id])

    if workflow.update(workflow_params)
      redirect_to company_project_workflows_path(current_project), notice: "Workflow updated"
    else
      redirect_to company_project_workflows_path(current_project), alert: workflow.errors.full_messages.join(", ")
    end
  end

  def destroy
    workflow = current_project.workflows.find(params[:id])
    workflow.destroy
    redirect_to company_project_workflows_path(current_project), notice: "Workflow deleted"
  end

  private

  def create_from_template!
    version = find_template_version!
    workflow = WorkflowTemplateInstantiator.new(
      project: current_project,
      version: version,
      user: current_user
    ).instantiate!(name: template_name_param)

    redirect_to builder_company_project_workflow_path(current_project, workflow), notice: "Workflow created from template"
  rescue WorkflowTemplateInstantiator::Error, ActiveRecord::RecordNotFound => e
    redirect_to company_project_workflows_path(current_project), alert: e.message
  end

  def find_template_version!
    WorkflowTemplateVersion
      .joins(:workflow_template)
      .merge(WorkflowTemplate.visible_to(current_user, current_company))
      .find(params.dig(:workflow, :workflow_template_version_id) || params[:workflow_template_version_id])
  end

  def template_name_param
    params.dig(:workflow, :name).presence
  end

  def workflow_params
    params.require(:workflow).permit(:name, :description, :workflow_template_version_id, config: {})
  end
end
