# frozen_string_literal: true

class AssetVersionResource < ApplicationResource
  attributes :id, :version, :content_type, :file_size, :source, :uploaded_by_id

  typelize :string?
  attribute :file_url do |version|
    version.file&.url
  end

  attribute :created_at do |version|
    version.created_at&.iso8601
  end
end
