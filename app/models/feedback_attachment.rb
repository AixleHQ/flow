# frozen_string_literal: true

# A file sent with a feedback message: a screenshot, a log, a recording.
class FeedbackAttachment < ApplicationRecord
  MAX_SIZE = 20.megabytes

  include FeedbackAttachmentUploader::Attachment(:file)

  belongs_to :feedback_submission

  validates :name, presence: true
  validates :file, presence: true
end
