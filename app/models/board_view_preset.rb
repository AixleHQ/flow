# frozen_string_literal: true

class BoardViewPreset < ApplicationRecord
  belongs_to :board
  belongs_to :user

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[board_id user_id] }
  validates :filters, presence: true

  scope :personal, ->(user) { where(user: user) }
  scope :shared_presets, -> { where(shared: true) }
  scope :visible_to, ->(user) { personal(user).or(shared_presets) }
end
