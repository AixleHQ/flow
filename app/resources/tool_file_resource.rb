# frozen_string_literal: true

class ToolFileResource < ApplicationResource
  attributes :id, :path, :content, :created_at, :updated_at

  typelize :boolean
  attribute :binary do |tool_file|
    tool_file.binary?
  end

  typelize :string?
  attribute :file_name do |tool_file|
    tool_file.binary? ? File.basename(tool_file.path) : nil
  end

  typelize :string?
  attribute :file_url do |tool_file|
    tool_file.binary? ? tool_file.file_url : nil
  end
end
