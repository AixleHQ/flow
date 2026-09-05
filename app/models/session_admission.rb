# frozen_string_literal: true

class SessionAdmission < ApplicationRecord
  belongs_to :terminal_session
  belongs_to :session_admission_pool
  has_many :session_runtime_operations, dependent: :destroy
  scope :unreleased, -> { where(released_at: nil) }
  scope :occupied, -> { unreleased.where.not(admitted_at: nil) }
end
