# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class AssetsController < Task::ApplicationController
            def index
              assets = current_task.task_assets.order(created_at: :desc)
              assets = assets.with_tag(params[:tag]) if params[:tag].present?
              render json: assets.map { |a| TaskAssetResource.new(a).to_h }
            end

            def create
              asset = TaskService.add_asset(task: current_task, params: asset_params, actor: current_user)
              render json: TaskAssetResource.new(asset).to_h, status: :created
            end

            def destroy
              asset = current_task.task_assets.find(params[:id])
              TaskService.destroy_asset(task: current_task, asset: asset, actor: current_user)
              head :no_content
            end

            private

            def asset_params
              params.require(:task_asset).permit(:name, :file, tags: [])
            end
          end
        end
      end
    end
  end
end
