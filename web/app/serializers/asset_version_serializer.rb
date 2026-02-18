# frozen_string_literal: true

class AssetVersionSerializer < ApplicationSerializer
  attributes :id, :version, :content_type, :file_size,
             :uploaded_by_id, :source,
             :file_url, :created_at

  def file_url
    object.file&.url
  end
end
