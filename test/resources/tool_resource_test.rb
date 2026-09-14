# frozen_string_literal: true

require "test_helper"

class ToolResourceTest < ActiveSupport::TestCase
  # Regression for a bug where `many :tool_files, resource: ToolFileResource` came
  # back as a Hash (e.g. `{}`, or `{fileHash => nil, ...}`) instead of an Array.
  # Alba calls `to_h` on the association resource once, wrapping the whole
  # `tool_files` collection, and ApplicationResource#to_h's camelizing pass assumed
  # its input was always a single record's attribute Hash. See
  # ApplicationResource#to_h for the fix.
  test "tool_files serializes as an array when the tool has files" do
    tool = create(:tool, :with_files)

    tool_files = ToolResource.new(tool).to_h["toolFiles"]

    assert_kind_of Array, tool_files
    assert_equal %w[/workspace/main.py /workspace/config.yaml], tool_files.map { |f| f["path"] }
  end

  test "tool_files serializes as an empty array when the tool has no files" do
    tool = create(:tool)

    tool_files = ToolResource.new(tool).to_h["toolFiles"]

    assert_equal [], tool_files
  end
end
