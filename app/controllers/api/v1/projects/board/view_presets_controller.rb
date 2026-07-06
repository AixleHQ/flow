# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class ViewPresetsController < Board::ApplicationController
          def index
            presets = current_board.board_view_presets.visible_to(current_user).order(:name)
            render json: presets.map { |p| BoardViewPresetResource.new(p).to_h }
          end

          def create
            preset = current_board.board_view_presets.build(preset_params)
            preset.user = current_user
            preset.save!
            render json: BoardViewPresetResource.new(preset).to_h, status: :created
          end

          def destroy
            preset = current_board.board_view_presets.find(params[:id])
            unless preset.user_id == current_user.id
              head :forbidden
              return
            end
            preset.destroy!
            head :no_content
          end

          private

          def preset_params
            p = params.require(:board_view_preset)
            filters = p[:filters]
            # Use permit!.to_h instead of to_unsafe_h — both allow arbitrary keys,
            # but permit! goes through ActionController::Parameters and is logged
            filters = filters.is_a?(ActionController::Parameters) ? filters.permit!.to_h : (filters || {})
            p.permit(:name, :shared).merge(filters: filters)
          end
        end
      end
    end
  end
end
