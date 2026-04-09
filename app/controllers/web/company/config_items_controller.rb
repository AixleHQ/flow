# frozen_string_literal: true

class Web::Company::ConfigItemsController < Web::Company::ApplicationController
  def index
    items = ConfigItem.for_company(current_company).order(:name)

    render inertia: "Company/ConfigItems/Index", props: {
      config_items: items.map { |i| ConfigItemResource.new(i).to_h }
    }
  end

  def create
    item = ConfigItem.new(create_params.merge(scope: current_company))

    if item.save
      redirect_to company_config_items_path, notice: "Config item created"
    else
      redirect_to company_config_items_path, inertia: { errors: item.errors }
    end
  end

  def update
    item = ConfigItem.for_company(current_company).find(params[:id])

    if item.update(update_params)
      redirect_to company_config_items_path, notice: "Config item updated"
    else
      redirect_to company_config_items_path, inertia: { errors: item.errors }
    end
  end

  def destroy
    item = ConfigItem.for_company(current_company).find(params[:id])
    item.destroy
    redirect_to company_config_items_path, notice: "Config item deleted"
  end

  private

  def create_params
    params.require(:config_item).permit(:name, :value, :description, :item_type)
  end

  def update_params
    params.require(:config_item).permit(:name, :value, :description, :item_type)
  end
end
