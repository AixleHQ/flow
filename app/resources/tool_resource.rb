# frozen_string_literal: true

class ToolResource < ApplicationResource
  attributes :id, :name, :display_name, :description, :kind, :scope_type, :scope_id,
             :docker_image, :command,
             :enabled, :created_at, :updated_at

  # required_config_items / input_schema are free-form jsonb columns; column
  # inference can only see `unknown`. Expose them as explicit attributes so the
  # keyless `typelize` annotation applies (the keyed form is gated by
  # Typelizer.enabled? at load time and is unreliable).
  typelize "Record<string, unknown>[]"
  attribute :required_config_items do |tool|
    tool.required_config_items
  end

  typelize "Record<string, unknown>"
  attribute :input_schema do |tool|
    tool.input_schema
  end

  typelize :boolean
  attribute :platform_tool do |tool|
    tool.platform_tool?
  end

  typelize %w[system company project]
  attribute :scope_indicator do |tool|
    tool.scope_indicator
  end

  many :tool_files, resource: ToolFileResource
end
