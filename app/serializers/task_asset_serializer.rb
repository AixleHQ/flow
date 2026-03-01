# frozen_string_literal: true

class TaskAssetSerializer < ApplicationSerializer
  attributes :id, :name, :file_url, :file_size, :content_type,
             :tags, :author_id, :author_type, :created_at, :updated_at

  def file_url
    object.file&.url
  end

  def file_size
    object.file&.metadata&.dig("size")
  end

  def content_type
    object.file&.metadata&.dig("mime_type")
  end
end
