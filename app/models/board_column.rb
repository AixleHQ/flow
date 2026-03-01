# frozen_string_literal: true

class BoardColumn < ApplicationRecord
  belongs_to :board
  has_one :column_workflow_binding, dependent: :destroy
  has_many :board_tasks, dependent: :restrict_with_error

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :board_id }

  before_validation :assign_next_position, on: :create
  after_save :detach_preset
  after_destroy :detach_preset

  def self.ransackable_attributes(_auth_object = nil)
    %w[name position purpose created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[board]
  end

  private

  def assign_next_position
    return if position.present?

    self.position = (board&.board_columns&.maximum(:position).to_i) + 1
  end

  def detach_preset
    board.update_column(:preset_origin, nil) if board.preset_origin.present?
  end
end
