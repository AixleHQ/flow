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
      board = create!(project: project, name: name || preset[:display_name])
      preset[:columns].each do |col_def|
        board.board_columns.create!(name: col_def[:name], position: col_def[:position], purpose: col_def[:purpose])
      end
      board.update_column(:preset_origin, preset_key.to_s)
      board
    end
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
