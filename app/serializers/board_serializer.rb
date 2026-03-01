# frozen_string_literal: true

class BoardSerializer < ApplicationSerializer
  attributes :id, :name, :preset_origin, :created_at, :updated_at

  has_many :board_columns, if: :include_associations
end
