# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          class ViewPresetsController < Api::V1::Company::Projects::ApplicationController
            def index
              presets = current_board.board_view_presets.visible_to(current_user).order(:name)
              respond_with presets, each_serializer: BoardViewPresetSerializer
            end

            def create
              preset = current_board.board_view_presets.build(preset_params)
              preset.user = current_user
              preset.save
              respond_with preset, serializer: BoardViewPresetSerializer
            end

            def destroy
              preset = current_board.board_view_presets.find(params[:id])
              unless preset.user_id == current_user.id || current_project.admin?(current_user)
                return head :forbidden
              end

              preset.destroy
              head :no_content
            end

            private

            def current_board
              @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
            end

            def preset_params
              params.require(:board_view_preset).permit(:name, :shared, filters: {})
            end
          end
        end
      end
    end
  end
end
