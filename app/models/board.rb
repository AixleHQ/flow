# frozen_string_literal: true

class Board < ApplicationRecord
  belongs_to :project
  has_many :board_tasks, dependent: :destroy
  has_many :board_columns, -> { order(:position) }, dependent: :destroy
  has_many :board_activities, dependent: :destroy
  has_many :board_view_presets, dependent: :destroy

  validates :name, presence: true
  validates :project_id, uniqueness: true

  after_commit :broadcast_updates, on: :update

  def self.create_from_preset(project:, preset_key:, name: nil)
    preset = BoardPresets.find(preset_key)
    raise ActiveRecord::RecordNotFound, "Invalid preset: #{preset_key}" unless preset

    transaction do
      board = create_from_columns(project: project, name: name || preset[:display_name], columns: preset[:columns])
      board.update_column(:preset_origin, preset_key.to_s)
      board
    end
  end

  # @param columns [Array<Hash>] `{ name:, purpose: }` in board order; an
  #   explicit `position:` is honoured, otherwise the list order is used.
  def self.create_from_columns(project:, name:, columns:)
    transaction do
      board = create!(project: project, name: name)
      columns.each_with_index do |col_def, index|
        col_def = col_def.to_h.symbolize_keys
        board.board_columns.create!(name: col_def[:name], position: col_def[:position] || (index + 1), purpose: col_def[:purpose])
      end
      board
    end
  end

  # Bumping and reading the counter in one UPDATE row-locks the board until the
  # transaction ends, so concurrent creates on one board get distinct numbers.
  # The counter only grows: a deleted task's number is never handed out again.
  def next_task_number!
    self.class.connection.select_value(self.class.sanitize_sql_array([ <<~SQL.squish, id ]))
      UPDATE boards SET last_task_number = last_task_number + 1 WHERE id = ? RETURNING last_task_number
    SQL
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name preset_origin created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[project board_columns]
  end

  private

  def broadcast_updates
    broadcast_refresh_to(self)
  end
end
