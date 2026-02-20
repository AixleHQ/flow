# frozen_string_literal: true

class SessionLog < ApplicationRecord
  include SessionLogUploader::Attachment(:file)

  belongs_to :terminal_session

  validates :name, presence: true
  validates :terminal_session, presence: true
end
