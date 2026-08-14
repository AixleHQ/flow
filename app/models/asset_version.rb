# frozen_string_literal: true

class AssetVersion < ApplicationRecord
  extend Enumerize
  include AssetFileUploader::Attachment(:file)

  belongs_to :asset, inverse_of: :versions
  belongs_to :uploaded_by, class_name: "User"

  enumerize :source, in: %i[upload workflow github session slack], default: :upload, predicates: true

  validates :version, presence: true

  before_validation :set_version, on: :create
  before_validation :derive_file_metadata, on: :create

  def self.ransackable_attributes(_auth_object = nil)
    %w[id asset_id version source uploaded_by_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[asset uploaded_by]
  end

  private

  def set_version
    self.version = (asset&.versions&.maximum(:version) || 0) + 1
  end

  # Browser uploads go straight to S3 and post back only the cached-file
  # descriptor, so nothing on that path ever sets file_size/content_type: the
  # Assets list showed "—" for every UI-uploaded asset, and OutputValidator's
  # minimum-size guard passed silently on `nil.to_i == 0`. Shrine's
  # restore_cached_data plugin re-extracts both from the cached file
  # server-side, so derive them here rather than trusting the client (file_size
  # is deliberately not a permitted param). Explicit values still win — the
  # agent paths (WorkflowStepStrategy, AgentSessionStrategy, Slack::FileIngestor)
  # set content_type from the source they already know.
  def derive_file_metadata
    metadata = file&.metadata
    return if metadata.blank?

    self.file_size = metadata["size"] if file_size.nil?
    self.content_type = metadata["mime_type"] if content_type.blank?
  end
end
