# frozen_string_literal: true

class ToolSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :display_name, :description, :kind, :scope_type, :scope_id,
             :docker_image, :command, :required_config_items, :input_schema,
             :enabled, :platform_tool, :created_at, :updated_at

  has_many :tool_files, serializer: ToolFileSerializer

  def platform_tool
    object.platform_tool?
  end
end
