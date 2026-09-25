# frozen_string_literal: true

class Web::Company::Projects::ToolsController < Web::Company::Projects::ApplicationController
  def index
    tools = Tool.visible_for_project(current_project)
                .ui_visible
                .includes(:tool_files)
                .order(source: :desc, created_at: :desc) # "db" (custom) before "code" (platform)
    config_items = ConfigItem.visible_for_project(current_project).pluck(:name)
    archived = Tool.db_source.deleted.where(scope_type: "Project", scope_id: current_project.id)
                   .includes(:tool_files).order(deleted_at: :desc)

    render inertia: "Projects/Tools/ToolsPage", props: {
      project: project_props,
      tools: tools.map { |t| ToolResource.new(t).to_h },
      archived_tools: archived.map { |t| ToolResource.new(t).to_h },
      config_item_names: config_items
    }
  end

  def create
    tool = current_project.tools.new(tool_params)
    Versions.save!(tool, actor: version_actor) { tool.save! }
    redirect_to company_project_tools_path(current_project), notice: "Tool created"
  rescue ActiveRecord::RecordInvalid
    redirect_to company_project_tools_path(current_project), inertia: { errors: tool.errors }
  end

  def update
    tool = current_project.tools.not_deleted.find(params[:id])
    Versions.save!(tool, actor: version_actor, base_version: params[:base_version]) { tool.update!(tool_params) }
    redirect_to company_project_tools_path(current_project), notice: "Tool updated"
  rescue ActiveRecord::RecordInvalid
    redirect_to company_project_tools_path(current_project), inertia: { errors: tool.errors }
  end

  def destroy
    tool = current_project.tools.not_deleted.find(params[:id])
    Versions.archive!(tool, actor: version_actor)
    redirect_to company_project_tools_path(current_project), notice: "Tool archived"
  end

  private

  def tool_params
    params.require(:tool).permit(
      :name, :display_name, :description, :docker_image, :command, :enabled,
      required_config_items: [],
      input_schema: {},
      tool_files_attributes: %i[id path content file _destroy]
    )
  end
end
