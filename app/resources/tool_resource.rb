# frozen_string_literal: true

class ToolResource < ApplicationResource
  attributes :id, :name, :display_name, :description, :kind, :scope_type, :scope_id,
             :docker_image, :command, :required_config_items, :input_schema,
             :enabled, :created_at, :updated_at

  attribute :platform_tool do |tool|
    tool.platform_tool?
  end

  attribute :scope_indicator do |tool|
    tool.scope_indicator
  end

  many :tool_files, resource: ToolFileResource
end
