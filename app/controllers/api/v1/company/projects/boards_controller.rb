# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class BoardsController < ApplicationController
          def show
            board = current_project.board
            if board
              board = ::Board.includes(board_columns: { column_workflow_binding: :workflow }).find(board.id)
              respond_with board, serializer: BoardSerializer
            else
              head :not_found
            end
          end

          def create
            if current_project.board.present?
              head :unprocessable_entity
              return
            end

            if params[:board][:preset].present?
              create_from_preset
            else
              board = current_project.build_board(board_params)
              board.save
              respond_with board, serializer: BoardSerializer
            end
          end

          def update
            board = current_project.board || raise(ActiveRecord::RecordNotFound)
            board.update(board_params)
            respond_with board, serializer: BoardSerializer
          end

          def destroy
            board = current_project.board || raise(ActiveRecord::RecordNotFound)
            board.destroy
            respond_with board
          end

          def presets
            respond_with BoardPresets.all
          end

          private

          def create_from_preset
            preset_key = params[:board][:preset]
            unless BoardPresets.valid?(preset_key)
              board = current_project.build_board(name: "invalid")
              board.errors.add(:preset, "is not a valid preset key")
              respond_with board, serializer: BoardSerializer
              return
            end

            board = ::Board.create_from_preset(
              project: current_project,
              preset_key: preset_key,
              name: params[:board][:name]
            )
            respond_with board, serializer: BoardSerializer
          rescue ActiveRecord::RecordInvalid => e
            respond_with e.record, serializer: BoardSerializer
          end

          def board_params
            params.require(:board).permit(:name)
          end
        end
      end
    end
  end
end
