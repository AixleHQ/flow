# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          class ColumnsController < Api::V1::Company::Projects::ApplicationController
            def index
              columns = current_board.board_columns.order(:position)
              respond_with columns, each_serializer: BoardColumnSerializer
            end

            def show
              column = current_board.board_columns.find(params[:id])
              respond_with column, serializer: BoardColumnSerializer
            end

            def create
              column = current_board.board_columns.build(column_params)
              column.save
              respond_with column, serializer: BoardColumnSerializer
            end

            def update
              column = current_board.board_columns.find(params[:id])
              column.update(column_params)
              respond_with column, serializer: BoardColumnSerializer
            end

            def destroy
              column = current_board.board_columns.find(params[:id])
              column.destroy!
              compact_positions(current_board)
              head :no_content
            end

            def reorder
              ActiveRecord::Base.transaction do
                offset = current_board.board_columns.count + 1
                params[:column_ids].each_with_index do |id, index|
                  current_board.board_columns.find(id).update_column(:position, offset + index + 1)
                end
                params[:column_ids].each_with_index do |id, index|
                  current_board.board_columns.find(id).update_column(:position, index + 1)
                end
                current_board.update_column(:preset_origin, nil) if current_board.preset_origin.present?
              end
              respond_with current_board.board_columns.reload.order(:position),
                           each_serializer: BoardColumnSerializer
            end

            private

            def current_board
              @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
            end

            def column_params
              params.require(:board_column).permit(:name, :purpose)
            end

            def compact_positions(board)
              board.board_columns.order(:position).each_with_index do |col, idx|
                col.update_column(:position, idx + 1)
              end
            end
          end
        end
      end
    end
  end
end
