# frozen_string_literal: true

class SessionArtifactSerializer < ApplicationSerializer
  attributes :id, :name, :folder, :status, :file_size, :content_type, :download_url, :created_at

  def file_size
    object.latest_version&.file_size
  end

  def content_type
    object.latest_version&.content_type
  end

  def download_url
    version = object.latest_version
    return nil unless version&.file.present?

    version.file_url(
      response_content_disposition: ::ContentDisposition.attachment(object.name)
    )
  end
end
