# frozen_string_literal: true

class ToolSerializer < ApplicationSerializer
  attributes :id, :name, :display_name, :description, :kind, :scope_type, :scope_id,
             :docker_image, :command, :required_config_items, :input_schema,
             :enabled, :scope_indicator, :platform_tool, :created_at, :updated_at

  has_many :tool_files, serializer: ToolFileSerializer

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.platform_tool?
      object.kind.to_s
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end

  def platform_tool
    object.platform_tool?
  end
end
