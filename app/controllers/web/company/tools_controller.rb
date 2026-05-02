# frozen_string_literal: true

class Web::Company::ToolsController < Web::Company::ApplicationController
  def index
    tools = Tool.visible_for_company(current_company)
                .includes(:tool_files)
                .order(kind: :asc, created_at: :desc)

    config_items = current_company.config_items.pluck(:name)

    render inertia: "Company/Tools/Index", props: {
      tools: tools.map { |t| ToolResource.new(t).to_h },
      config_item_names: config_items
    }
  end

  def create
    tool = current_company.tools.new(tool_params)

    if tool.save
      redirect_to company_tools_path, notice: "Tool created"
    else
      redirect_to company_tools_path, inertia: { errors: tool.errors }
    end
  end

  def update
    tool = current_company.tools.active.find(params[:id])

    if tool.update(tool_params)
      redirect_to company_tools_path, notice: "Tool updated"
    else
      redirect_to company_tools_path, inertia: { errors: tool.errors }
    end
  end

  def destroy
    tool = current_company.tools.active.find(params[:id])
    tool.soft_delete!
    redirect_to company_tools_path, notice: "Tool deleted"
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
