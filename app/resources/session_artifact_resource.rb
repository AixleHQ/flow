# frozen_string_literal: true

class SessionArtifactResource < ApplicationResource
  attributes :id, :name, :folder, :status, :created_at

  attribute :file_size do |asset|
    asset.latest_version&.file_size
  end

  attribute :content_type do |asset|
    asset.latest_version&.content_type
  end

  attribute :download_url do |asset|
    version = asset.latest_version
    next nil unless version&.file.present?

    version.file_url(
      response_content_disposition: ::ContentDisposition.attachment(asset.name)
    )
  end
end
