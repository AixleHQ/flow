# frozen_string_literal: true

class BoardResource < ApplicationResource
  attributes :id, :name, :preset_origin, :created_at, :updated_at

  attribute :board_columns, if: proc { params[:include_columns] } do |board|
    board.board_columns.order(:position).map { |c| BoardColumnResource.new(c).to_h }
  end
end
