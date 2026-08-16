# frozen_string_literal: true

class BoardResource < ApplicationResource
  attributes :id, :name, :preset_origin, :created_at, :updated_at

  typelize "BoardColumn[]"
  attribute :board_columns, if: proc { params[:include_columns] } do |board|
    # params carries `snake_keys` through to the nested columns.
    board.board_columns.with_tasks_count.order(:position).map { |c| BoardColumnResource.new(c, params: params).to_h }
  end
end
