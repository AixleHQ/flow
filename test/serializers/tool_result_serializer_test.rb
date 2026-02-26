# frozen_string_literal: true

require "test_helper"

class ToolResultSerializerTest < ActiveSupport::TestCase
  setup do
    @tool = create(:tool, :internal, name: "ser_test", display_name: "Ser Test")
  end

  test "serializes completed result with attachments" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 0, stdout: '{"ok": true}', stderr: "warn", duration_ms: 500)
    tr.reload

    json = JSON.parse(ToolResultSerializer.new(tr).to_json)

    assert_equal tr.execution_id, json["execution_id"]
    assert_equal "ser_test", json["tool_name"]
    assert_equal "completed", json["state"]
    assert_equal 0, json["exit_code"]
    assert_nil json["error"]
    assert_equal 500, json["duration_ms"]
    assert json["stdout_url"].present?
    assert json["stdout_size"].present?
    assert json["stderr_url"].present?
    assert json["result_data_url"].present?
    assert_nil json["output_url"]
    assert_nil json["output_size"]
  end

  test "serializes processing result with nil URLs" do
    tr = create(:tool_result, tool: @tool)

    json = JSON.parse(ToolResultSerializer.new(tr).to_json)

    assert_equal "processing", json["state"]
    assert_nil json["exit_code"]
    assert_nil json["stdout_url"]
    assert_nil json["stderr_url"]
    assert_nil json["result_data_url"]
    assert_nil json["output_url"]
  end

  test "serialized payload is compact" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 0, stdout: '{"a":1}', stderr: "", duration_ms: 100)
    tr.reload

    payload = ToolResultSerializer.new(tr).to_json
    assert payload.bytesize < 1000, "Payload should be compact, was #{payload.bytesize} bytes"
  end
end
