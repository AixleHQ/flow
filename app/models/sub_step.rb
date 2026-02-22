# frozen_string_literal: true

class SubStep < ApplicationRecord
  belongs_to :step

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :step_id }

  default_scope { order(:position) }
end
