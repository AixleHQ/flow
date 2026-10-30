# frozen_string_literal: true

# What someone sent from the Send feedback dialog. Kept so that each configured
# destination receives it once and is retried on its own (Feedback::DeliverJob).
class FeedbackSubmission < ApplicationRecord
  extend Enumerize

  MESSAGE_MAX = 5000
  PAGE_URL_MAX = 2048
  HOURLY_LIMIT = 10
  ATTACHMENTS_MAX = 5

  belongs_to :company
  belongs_to :user, optional: true
  # Validated below, so a refused file is named instead of "Attachments is invalid".
  has_many :attachments, class_name: "FeedbackAttachment", dependent: :destroy, validate: false

  enumerize :kind, in: %i[bug feature_request support]

  validates :user, presence: true, on: :create
  validates :kind, presence: true
  validates :message, presence: true, length: { maximum: MESSAGE_MAX }
  validates :page_url, length: { maximum: PAGE_URL_MAX }
  validate :within_hourly_limit, on: :create
  validate :attachments_acceptable

  # Uploaded files from the form, each kept under the name it was sent with.
  def attach(files)
    files.each { |file| attachments.build(name: file.original_filename.presence || "file", file: file) }
  end

  private

  def within_hourly_limit
    return if user.nil?
    return if FeedbackSubmission.where(user: user, created_at: 1.hour.ago..).count < HOURLY_LIMIT

    errors.add(:base, "You have sent #{HOURLY_LIMIT} messages in the last hour. Please try again later.")
  end

  def attachments_acceptable
    if attachments.size > ATTACHMENTS_MAX
      errors.add(:base, "Attach at most #{ATTACHMENTS_MAX} files.")
      return
    end

    attachments.reject(&:valid?).each do |attachment|
      errors.add(:base, "#{attachment.name} #{attachment.errors[:file].first || 'could not be attached'}.")
    end
  end
end
