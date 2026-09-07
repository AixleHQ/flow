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
            ordered = ordered_for_reorder(current_board.board_columns.order(:position).to_a)

            ActiveRecord::Base.transaction do
              # Position is unique per board, so the new numbering cannot be
              # written over the old one in place. Everything parks above the
              # highest number currently in use — free by definition — and then
              # comes back down as a contiguous 1..n.
              offset = current_board.board_columns.maximum(:position).to_i
              ordered.each_with_index { |column, index| column.update_column(:position, offset + index + 1) }
              ordered.each_with_index { |column, index| column.update_column(:position, index + 1) }
              current_board.update_column(:preset_origin, nil) if current_board.preset_origin.present?
            end

            reordered = current_board.board_columns.reload.with_tasks_count.order(:position)
            render json: reordered.map { |c| BoardColumnResource.new(c).to_h }
          end

          private

          # The named columns in the order given, then whatever the payload left
          # out, keeping its relative order. Renumbering only the named ones
          # collided with the columns it did not name, and the board settings
          # dialog sends a partial list whenever a column appears while it is
          # open or a create in the same save fails. Unknown and repeated ids
          # are dropped rather than failing the whole reorder over a column
          # someone else has already deleted.
          def ordered_for_reorder(columns)
            by_id = columns.index_by(&:id)
            named = Array(params[:column_ids]).map(&:to_i).uniq.filter_map { |id| by_id[id] }
            named + (columns - named)
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
