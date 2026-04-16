# frozen_string_literal: true

module Api
  module V1
    module Projects
      class BoardController < ApplicationController
        def create
          if current_project.board.present?
            head :unprocessable_entity
            return
          end

          if params[:board][:preset].present?
            create_from_preset
          else
            board = current_project.build_board(board_params)
            board.save!
            render json: BoardResource.new(board).to_h, status: :created
          end
        end

        def update
          board = current_project.board || raise(ActiveRecord::RecordNotFound)
          board.update!(board_params)
          render json: BoardResource.new(board).to_h
        end

        def destroy
          board = current_project.board || raise(ActiveRecord::RecordNotFound)
          board.destroy
          head :no_content
        end

        private

        def create_from_preset
          preset_key = params[:board][:preset]
          unless BoardPresets.valid?(preset_key)
            render json: { errors: [ "Invalid preset key" ] }, status: :unprocessable_entity
            return
          end

          board = ::Board.create_from_preset(
            project: current_project,
            preset_key: preset_key,
            name: params[:board][:name]
          )
          render json: BoardResource.new(board).to_h, status: :created
        end

        def board_params
          params.require(:board).permit(:name)
        end
      end
    end
  end
end
