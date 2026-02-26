# frozen_string_literal: true

# ToolFile — file to mount into container at tool execution time.
# Supports both text content (legacy `content` column) and binary files via Shrine (S3).
# When `file` attachment is present, it takes precedence over `content`.
class ToolFile < ApplicationRecord
  include ToolFileUploader::Attachment(:file)

  belongs_to :tool

  validates :path, presence: true,
                   format: { with: %r{\A/workspace/.+\z}, message: "must start with /workspace/" },
                   uniqueness: { scope: :tool_id, message: "already exists for this tool" }
  validate :content_or_file_present

  def binary?
    file.present?
  end

  def text_content
    content.presence || (file && file.read)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[path created_at updated_at]
  end

  private

  def content_or_file_present
    return if content.present? || file.present?

    errors.add(:base, "must have either content or file")
  end
end
