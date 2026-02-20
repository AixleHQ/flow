# frozen_string_literal: true

class SessionLogSerializer < ApplicationSerializer
  attributes :id, :name, :file_size, :content_type, :download_url, :created_at

  def download_url
    return nil unless object.file.present?

    object.file_url(
      response_content_disposition: ::ContentDisposition.attachment(object.name)
    )
  end
end
