# frozen_string_literal: true

class Web::Company::Projects::ConfigItemsController < Web::Company::Projects::ApplicationController
  def index
    items = ConfigItem.visible_for_project(current_project).order(:name)

    render inertia: "Projects/Config/ConfigPage", props: {
      project: project_props,
      config_items: items.map { |i| ConfigItemResource.new(i).to_h }
    }
  end

  def create
    item = ConfigItem.new(config_item_params.merge(scope: current_project))

    if item.save
      redirect_to company_project_config_items_path(current_project), notice: "Config item created"
    else
      redirect_to company_project_config_items_path(current_project), inertia: { errors: item.errors }
    end
  end

  def update
    item = ConfigItem.visible_for_project(current_project).find(params[:id])

    if item.update(config_item_params)
      redirect_to company_project_config_items_path(current_project), notice: "Config item updated"
    else
      redirect_to company_project_config_items_path(current_project), inertia: { errors: item.errors }
    end
  end

  def destroy
    item = ConfigItem.visible_for_project(current_project).find(params[:id])
    item.destroy
    redirect_to company_project_config_items_path(current_project), notice: "Config item deleted"
  end

  private

  def config_item_params
    params.require(:config_item).permit(:name, :value, :description, :item_type)
  end
end
