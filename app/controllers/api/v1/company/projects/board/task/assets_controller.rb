# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class AssetsController < Api::V1::Company::Projects::ApplicationController
              def index
                assets = current_task.task_assets.order(created_at: :desc)
                assets = assets.with_tag(params[:tag]) if params[:tag].present?
                respond_with assets, each_serializer: TaskAssetSerializer
              end

              def create
                asset = current_task.task_assets.build(asset_params)
                asset.author = current_user
                asset.author_type = :human
                if asset.save
                  ActivityRecorder.record(
                    board: current_board, event_type: :asset_attached, actor: current_user,
                    actor_type: :human, task: current_task,
                    metadata: { name: asset.name, content_type: asset.file&.metadata&.dig("mime_type") }
                  )
                end
                respond_with asset, serializer: TaskAssetSerializer
              end

              def destroy
                asset = current_task.task_assets.find(params[:id])
                unless current_project.admin?(current_user) || asset.author_id == current_user.id
                  return head :forbidden
                end

                asset.destroy
                head :no_content
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end

              def asset_params
                params.require(:task_asset).permit(:name, :file, tags: [])
              end
            end
          end
        end
      end
    end
  end
end
