# frozen_string_literal: true

class SubStep < ApplicationRecord
  belongs_to :step

  validates :name, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end
