# frozen_string_literal: true

class ToolFileSerializer < ApplicationSerializer
  attributes :id, :path, :content, :binary, :file_name, :file_url, :created_at, :updated_at

  def binary
    object.binary?
  end

  def file_name
    return nil unless object.binary?

    File.basename(object.path)
  end

  def file_url
    return nil unless object.binary?

    object.file_url
  end
end
