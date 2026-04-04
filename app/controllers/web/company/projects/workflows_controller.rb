# frozen_string_literal: true

class Web::Company::Projects::WorkflowsController < Web::Company::Projects::ApplicationController
  def index
    workflows = Workflow.visible_for_project(@project)
                        .includes(:steps, :runs)

    respond_to do |format|
      format.json do
        render json: workflows.map { |w| WorkflowSerializer.new(w).as_json }
      end
      format.html do
        assets = @project.assets.active.includes(:versions)
        repositories = Repository.visible_for_project(@project)

        render inertia: "Projects/Workflows/WorkflowsPage", props: {
          project: project_props,
          workflows: workflows.map { |w|
            WorkflowResource.new(w).to_h.merge(
              steps: w.steps.not_deleted.map { |s|
                { id: s.id, name: s.name, position: s.position, allow_non_interactive: s.allow_non_interactive || false,
                  depends_on_step_ids: s.depends_on_step_ids || [] }
              }
            )
          },
          assets: assets.map { |a| { id: a.id, name: a.folder.present? ? "#{a.folder}/#{a.name}" : a.name } },
          repositories: repositories.map { |r| { id: r.id, name: r.full_name } },
          configured_agents: current_user.configured_agents
        }
      end
    end
  end

  def builder
    workflow = Workflow.visible_for_project(@project)
                      .includes(steps: :sub_steps)
                      .find(params[:id])

    is_read_only = workflow.scope_type == "Company"
    agents = Agent.visible_for_project(@project)
    tools = Tool.visible_for_project(@project)
    skills = Skill.visible_for_project(@project)
    mcp_servers = MCPServer.visible_for_project(@project)
    assets = @project.assets.active.includes(:versions)
    repositories = Repository.visible_for_project(@project)

    render inertia: "Projects/Workflows/BuilderPage", props: {
      project: project_props,
      workflow: WorkflowResource.new(workflow).to_h.merge(
        inherit_all_project_resources: workflow.inherit_all_project_resources || false,
        base_tool_ids: workflow.base_tool_ids || [],
        base_skill_ids: workflow.base_skill_ids || [],
        base_mcp_server_ids: workflow.base_mcp_server_ids || [],
        base_asset_ids: workflow.base_asset_ids || []
      ),
      steps: workflow.steps.not_deleted.map { |s| StepResource.new(s).to_h },
      agents: agents.map { |a| { id: a.id, name: a.title.presence || a.name } },
      tools: tools.map { |t| { id: t.id, name: t.display_name.presence || t.name } },
      skills: skills.map { |s| { id: s.id, name: s.title.presence || s.name } },
      mcp_servers: mcp_servers.map { |m| { id: m.id, name: m.display_name.presence || m.name } },
      assets: assets.map { |a| { id: a.id, name: a.folder.present? ? "#{a.folder}/#{a.name}" : a.name } },
      repositories: repositories.map { |r| { id: r.id, name: r.full_name } },
      read_only: is_read_only,
      configured_agents: current_user.configured_agents
    }
  end

  def create
    workflow = @project.workflows.new(workflow_params)
    if workflow.save
      redirect_to company_project_workflows_path(@project), notice: "Workflow created"
    else
      redirect_to company_project_workflows_path(@project), alert: workflow.errors.full_messages.join(", ")
    end
  end

  def show
    workflow = Workflow.visible_for_project(@project).find(params[:id])
    render json: WorkflowSerializer.new(workflow).as_json
  end

  def update
    workflow = @project.workflows.active.find(params[:id])
    if workflow.update(workflow_params)
      respond_to do |format|
        format.json { render json: WorkflowSerializer.new(workflow).as_json }
        format.html { redirect_to company_project_workflows_path(@project), notice: "Workflow updated" }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: workflow.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to company_project_workflows_path(@project), alert: workflow.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    workflow = @project.workflows.active.find(params[:id])
    if workflow.has_active_runs?
      respond_to do |format|
        format.json { render json: { error: "Cannot delete workflow with active runs" }, status: :unprocessable_entity }
        format.html { redirect_to company_project_workflows_path(@project), alert: "Cannot delete workflow with active runs" }
      end
      return
    end
    workflow.soft_delete!
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to company_project_workflows_path(@project), notice: "Workflow deleted" }
    end
  end

  private

  def workflow_params
    params.require(:workflow).permit(:name, :description, config: {})
  end
end
