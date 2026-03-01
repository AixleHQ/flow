# frozen_string_literal: true

require "test_helper"

class ToolResultCleanupJobTest < ActiveSupport::TestCase
  setup do
    @tool = create(:tool, :internal, name: "cleanup_test", display_name: "Cleanup Test")
  end

  test "expires old completed results" do
    tr = create(:tool_result, :completed, tool: @tool)
    tr.update_column(:created_at, 40.days.ago)

    ToolResultCleanupJob.new.perform

    tr.reload
    assert_equal "expired", tr.state
    assert_nil tr.stdout_data
    assert_nil tr.stderr_data
    assert_nil tr.result_data_data
    assert_nil tr.output_data
  end

  test "expires old failed results" do
    tr = create(:tool_result, :failed, tool: @tool)
    tr.update_column(:created_at, 35.days.ago)

    ToolResultCleanupJob.new.perform

    tr.reload
    assert_equal "expired", tr.state
  end

  test "preserves recent results" do
    tr = create(:tool_result, :completed, tool: @tool)

    ToolResultCleanupJob.new.perform

    tr.reload
    assert_equal "completed", tr.state
  end

  test "fails stuck processing results older than threshold" do
    tr = create(:tool_result, tool: @tool, state: "processing")
    tr.update_column(:created_at, 40.days.ago)

    ToolResultCleanupJob.new.perform

    tr.reload
    assert_equal "failed", tr.state
    assert_equal "Timed out: stuck in processing", tr.error
  end

  test "preserves audit columns after expiry" do
    tr = create(:tool_result, :completed, tool: @tool)
    tr.update_column(:created_at, 40.days.ago)

    ToolResultCleanupJob.new.perform

    tr.reload
    assert_equal "expired", tr.state
    assert tr.execution_id.present?
    assert tr.exit_code.present?
    assert tr.duration_ms.present?
  end
end
