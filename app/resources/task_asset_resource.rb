# frozen_string_literal: true

class TaskAssetResource < ApplicationResource
  attributes :id, :name, :tags, :author_id, :author_type, :created_at, :updated_at

  typelize "string"
  attribute :source do |asset|
    asset.source.to_s
  end

  # The tracker issue a copied file came from (docs/design/tracker-attachments.md §5).
  typelize "string | null"
  attribute :tracker_issue_key do |asset|
    asset.tracker_attachment&.issue_key if asset.source.tracker?
  end

  typelize "string | null"
  attribute :file_url do |asset|
    asset.file&.url
  end

  typelize "number | null"
  attribute :file_size do |asset|
    asset.file&.metadata&.dig("size")
  end

  typelize "string | null"
  attribute :content_type do |asset|
    asset.file&.metadata&.dig("mime_type")
  end

  typelize "string | null", optional: true
  attribute :share_url do |asset|
    asset.share_url
  end
end
