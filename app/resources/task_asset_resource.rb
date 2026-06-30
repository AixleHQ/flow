# frozen_string_literal: true

class TaskAssetResource < ApplicationResource
  attributes :id, :name, :tags, :author_id, :author_type, :created_at, :updated_at

  typelize :string?
  attribute :file_url do |asset|
    asset.file&.url
  end

  typelize :number?
  attribute :file_size do |asset|
    asset.file&.metadata&.dig("size")
  end

  typelize :string?
  attribute :content_type do |asset|
    asset.file&.metadata&.dig("mime_type")
  end
end
