# frozen_string_literal: true

module Api
  module V1
    module Company
      class ConfigItemsController < ApplicationController
        def index
          items = ConfigItem.for_company(current_company)
          respond_with items, each_serializer: ConfigItemSerializer
        end

        def create
          item = current_company.config_items.create(config_item_params)
          respond_with item
        end

        def update
          item = current_company.config_items.find(params[:id])
          item.update(config_item_params)
          respond_with item
        end

        def destroy
          item = current_company.config_items.find(params[:id])
          item.destroy
          respond_with item
        end

        private

        def config_item_params
          params.require(:config_item).permit(:name, :value, :description, :item_type)
        end
      end
    end
  end
end
