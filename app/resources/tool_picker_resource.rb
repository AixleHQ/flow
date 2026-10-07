# frozen_string_literal: true

# PickerResource plus the name the agent calls the tool by (`name` is the
# display name), so a `{{tool:…}}` reference can show both, and where it comes from.
class ToolPickerResource < PickerResource
  typelize :string
  attribute :tool_name do |tool|
    tool.name
  end

  typelize %w[system project]
  attribute :scope do |tool|
    tool.scope_indicator
  end
end
