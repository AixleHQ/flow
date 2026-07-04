# frozen_string_literal: true

class Web::Company::Projects::ToolsController < Web::Company::Projects::ApplicationController
  def index
    tools = Tool.visible_for_project(current_project)
                .ui_visible
                .includes(:tool_files)
                .order(source: :desc, created_at: :desc) # "db" (custom) before "code" (platform)
    config_items = current_company.config_items.pluck(:name)

    render inertia: "Projects/Tools/ToolsPage", props: {
      project: project_props,
      tools: tools.map { |t| ToolResource.new(t).to_h },
      config_item_names: config_items
    }
  end

  def create
    tool = current_project.tools.new(tool_params)

    if tool.save
      redirect_to company_project_tools_path(current_project), notice: "Tool created"
    else
      redirect_to company_project_tools_path(current_project), inertia: { errors: tool.errors }
    end
  end

  def update
    tool = current_project.tools.not_deleted.find(params[:id])

    if tool.update(tool_params)
      redirect_to company_project_tools_path(current_project), notice: "Tool updated"
    else
      redirect_to company_project_tools_path(current_project), inertia: { errors: tool.errors }
    end
  end

  def destroy
    tool = current_project.tools.not_deleted.find(params[:id])
    tool.soft_delete!
    redirect_to company_project_tools_path(current_project), notice: "Tool deleted"
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
