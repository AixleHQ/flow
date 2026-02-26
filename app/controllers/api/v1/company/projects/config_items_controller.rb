# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class ConfigItemsController < ApplicationController
          def index
            items = ConfigItem.visible_for_project(current_project)
            respond_with items, each_serializer: ConfigItemSerializer, project: current_project
          end

          def create
            item = current_project.config_items.create(config_item_params)
            respond_with item
          end

          def update
            item = current_project.config_items.find(params[:id])
            item.update(config_item_params)
            respond_with item
          end

          def destroy
            item = current_project.config_items.find(params[:id])
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
end
