# frozen_string_literal: true

class SessionLog < ApplicationRecord
  include SessionLogUploader::Attachment(:file)

  belongs_to :terminal_session

  validates :name, presence: true
  validates :terminal_session, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name content_type file_size terminal_session_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[terminal_session]
  end
end
