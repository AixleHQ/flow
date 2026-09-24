# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class ColumnsController < Board::ApplicationController
          def index
            columns = current_board.board_columns.with_tasks_count.order(:position)
            render json: columns.map { |c| BoardColumnResource.new(c).to_h }
          end

          def show
            column = current_board.board_columns.find(params[:id])
            render json: BoardColumnResource.new(column).to_h
          end

          def create
            column = current_board.board_columns.build(column_params)
            column.save!
            render json: BoardColumnResource.new(column).to_h, status: :created
          end

          def update
            column = current_board.board_columns.find(params[:id])
            column.update!(column_params)
            render json: BoardColumnResource.new(column).to_h
          end

          def destroy
            column = current_board.board_columns.find(params[:id])
            column.destroy!
            compact_positions(current_board)
            head :no_content
          rescue ActiveRecord::RecordNotDestroyed => e
            render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          # @summary Reorder board columns
          def reorder
            # The board settings dialog sends a partial list whenever a column
            # appears while it is open or a create in the same save fails; the
            # columns it left out keep their relative order after the named ones.
            ActiveRecord::Base.transaction do
              Positions.reorder!(current_board.board_columns, params[:column_ids])
              current_board.update_column(:preset_origin, nil) if current_board.preset_origin.present?
            end

            reordered = current_board.board_columns.reload.with_tasks_count.order(:position)
            render json: reordered.map { |c| BoardColumnResource.new(c).to_h }
          end

          private

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
