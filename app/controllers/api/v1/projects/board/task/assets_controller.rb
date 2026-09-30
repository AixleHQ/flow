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
              file = asset_params[:file]
              if file.present? && !file.respond_to?(:read)
                return render json: { error: "file must be an uploaded file" }, status: :unprocessable_entity
              end

              asset = TaskService.add_asset(task: current_task, params: asset_params, actor: current_user)
              if asset.persisted?
                render json: TaskAssetResource.new(asset).to_h, status: :created
              else
                render json: { error: asset.errors.full_messages.to_sentence, errors: asset.errors.full_messages },
                       status: :unprocessable_entity
              end
            end

            def destroy
              asset = current_task.task_assets.find(params[:id])
              TaskService.destroy_asset(task: current_task, asset: asset, actor: current_user)
              head :no_content
            end

            def unshare
              asset = current_task.task_assets.find(params[:id])
              asset.unshare!
              render json: TaskAssetResource.new(asset).to_h
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
