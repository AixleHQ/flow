# frozen_string_literal: true

class Web::Company::Projects::WorkflowsController < Web::Company::Projects::ApplicationController
  def index
    workflows = Workflow.visible_for_project(current_project)
                        .includes(:steps, :runs)

    render inertia: "Projects/Workflows/WorkflowsPage", props: {
      project: project_props,
      workflows: workflows.map { |w|
        WorkflowResource.new(w).to_h.merge(
          steps: w.steps.not_deleted.map { |s| StepResource.new(s).to_h }
        )
      },
      configured_agents: current_project_membership&.configured_agents || [],
      default_agent_runtime: current_project_membership&.default_agent_runtime,
      # Company-scoped assets are shared with every project in the company and are
      # already offered by the assets page, the session form and the Aixle Builder.
      # `current_project.assets` walks the has_many and sees project-owned rows only,
      # so the workflow builder was the one picker that could not reach them.
      assets: InertiaRails.defer(group: "resources") {
        Asset.accessible_from_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      repositories: InertiaRails.defer(group: "resources") {
        Repository.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      agent_models: InertiaRails.defer(group: "resources") {
        current_project_membership&.agent_models_for_props || []
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
      board_columns: current_project.board&.board_columns&.includes(column_workflow_binding: :workflow)&.map { |c|
        { id: c.id, name: c.name, bound_workflow_name: c.column_workflow_binding&.workflow&.name }
      } || [],
      configured_agents: current_project_membership&.configured_agents || [],
      default_agent_runtime: current_project_membership&.default_agent_runtime,
      agents: InertiaRails.defer(group: "resources") {
        Agent.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      tools: InertiaRails.defer(group: "resources") {
        Tool.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      # Tag groups the picker offers as one-click attach (e.g. "Board
      # management" → every board tool), resolved to this project's tool ids.
      tool_groups: InertiaRails.defer(group: "resources") {
        Tools::PickerGroups.for_project(current_project)
      },
      skills: InertiaRails.defer(group: "resources") {
        Skill.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      mcp_servers: InertiaRails.defer(group: "resources") {
        MCPServer.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      # Company-scoped assets are shared with every project in the company and are
      # already offered by the assets page, the session form and the Aixle Builder.
      # `current_project.assets` walks the has_many and sees project-owned rows only,
      # so the workflow builder was the one picker that could not reach them.
      assets: InertiaRails.defer(group: "resources") {
        Asset.accessible_from_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      repositories: InertiaRails.defer(group: "resources") {
        Repository.visible_for_project(current_project).map { |r| PickerResource.new(r).to_h }
      },
      agent_models: InertiaRails.defer(group: "resources") {
        current_project_membership&.agent_models_for_props || []
      }
    }
  end

  def create
    workflow = current_project.workflows.new(workflow_params)
    if workflow.save
      redirect_to company_project_workflows_path(current_project), notice: "Workflow created"
    else
      redirect_to company_project_workflows_path(current_project), alert: workflow.errors.full_messages.join(", ")
    end
  end

  def destroy
    workflow = current_project.workflows.find(params[:id])
    workflow.destroy
    redirect_to company_project_workflows_path(current_project), notice: "Workflow deleted"
  end

  def publish
    workflow = current_project.workflows.find(params[:id])
    workflow.publish!(current_user)
    redirect_to company_project_workflows_path(current_project), notice: "Workflow published to catalog"
  end

  def unpublish
    workflow = current_project.workflows.find(params[:id])

    unless current_project_membership&.admin? || workflow.published_by_id == current_user.id
      redirect_to company_project_workflows_path(current_project), alert: "Only the publisher or an admin can unpublish"
      return
    end

    workflow.unpublish!
    redirect_to company_project_workflows_path(current_project), notice: "Workflow removed from catalog"
  end

  def duplicate
    source = Workflow.visible_for_project(current_project).find(params[:id])
    duplicator = WorkflowDuplicator.new(source, target_scope: current_project)
    copy = duplicator.duplicate!
    flash[:needs_setup] = duplicator.summary[:needs_setup] if duplicator.summary
    redirect_to builder_company_project_workflow_path(current_project, copy)
  end

  private

  def workflow_params
    params.require(:workflow).permit(:name, :description, config: {})
  end
end
