# frozen_string_literal: true

require "test_helper"

class ToolResultTest < ActiveSupport::TestCase
  setup do
    @tool = create(:tool, :internal, name: "tr_test", display_name: "TR Test")
  end

  test "generate_id returns prefixed hex string" do
    id = ToolResult.generate_id
    assert_match(/\Atr-[a-f0-9]{24}\z/, id)
  end

  test "generate_id returns unique values" do
    ids = 10.times.map { ToolResult.generate_id }
    assert_equal 10, ids.uniq.size
  end

  test "complete! with exit_code 0 sets state to completed" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 0, stdout: "ok", stderr: "", duration_ms: 100)

    assert_equal "completed", tr.state
    assert_equal 0, tr.exit_code
    assert_nil tr.error
    assert_equal 100, tr.duration_ms
    assert tr.stdout.present?
  end

  test "complete! with exit_code != 0 sets state to failed" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 1, stdout: "", stderr: "error output", duration_ms: 200)

    assert_equal "failed", tr.state
    assert_equal 1, tr.exit_code
    assert_equal "Exited with code 1", tr.error
    assert tr.stderr.present?
  end

  test "complete! with error message sets state to failed" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 124, stdout: "", stderr: "", duration_ms: 600_000,
                 error: "Timed out after 600s")

    assert_equal "failed", tr.state
    assert_equal "Timed out after 600s", tr.error
  end

  test "complete! with JSON stdout populates result_data" do
    tr = create(:tool_result, tool: @tool)
    json_output = { "issues" => 5, "score" => 3.2 }.to_json
    tr.complete!(exit_code: 0, stdout: json_output, stderr: "", duration_ms: 300)

    assert_equal "completed", tr.state
    assert tr.stdout.present?
    assert tr.result_data.present?
  end

  test "complete! with non-JSON stdout leaves result_data nil" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 0, stdout: "just plain text", stderr: "", duration_ms: 50)

    assert_equal "completed", tr.state
    assert tr.stdout.present?
    assert_nil tr.result_data
  end

  test "complete! with empty stdout leaves stdout attachment nil" do
    tr = create(:tool_result, tool: @tool)
    tr.complete!(exit_code: 0, stdout: "", stderr: "", duration_ms: 10)

    assert_equal "completed", tr.state
    assert_nil tr.stdout
    assert_nil tr.stderr
  end

  test "stale scope returns old completed/failed records" do
    old_completed = create(:tool_result, :completed, tool: @tool)
    old_completed.update_column(:created_at, 40.days.ago)

    old_failed = create(:tool_result, :failed, tool: @tool)
    old_failed.update_column(:created_at, 35.days.ago)

    recent = create(:tool_result, :completed, tool: @tool)
    processing = create(:tool_result, tool: @tool)
    processing.update_column(:created_at, 40.days.ago)

    stale = ToolResult.stale(30.days)

    assert_includes stale, old_completed
    assert_includes stale, old_failed
    assert_not_includes stale, recent
    assert_not_includes stale, processing
  end

  test "validates state inclusion" do
    tr = build(:tool_result, tool: @tool, state: "invalid")
    assert_not tr.valid?
    assert tr.errors[:state].any?
  end

  test "validates execution_id presence" do
    tr = build(:tool_result, tool: @tool, execution_id: nil)
    assert_not tr.valid?
    assert tr.errors[:execution_id].any?
  end

  test "validates execution_id uniqueness" do
    create(:tool_result, tool: @tool, execution_id: "tr-unique123")
    tr2 = build(:tool_result, tool: @tool, execution_id: "tr-unique123")
    assert_not tr2.valid?
  end
end
