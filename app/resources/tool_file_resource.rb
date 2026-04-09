# frozen_string_literal: true

class ToolFileResource < ApplicationResource
  attributes :id, :path, :content, :created_at, :updated_at

  attribute :binary do |tool_file|
    tool_file.binary?
  end

  attribute :file_name do |tool_file|
    tool_file.binary? ? File.basename(tool_file.path) : nil
  end

  attribute :file_url do |tool_file|
    tool_file.binary? ? tool_file.file_url : nil
  end
end
