# frozen_string_literal: true

require "test_helper"
class PlatformToolsReconcileTest < ActiveSupport::TestCase
  test "seed creates board workflow tools" do
    Tools::Reconciler.run!

    %w[
      board_get_board_info
      board_list_tasks
      board_get_task
      board_get_comments
      board_get_task_assets
      board_add_comment
      board_update_task
      board_create_task
      board_move_task
      board_attach_asset
      board_manage_tags
      board_list_members
    ].each do |tool_name|
      tool = Tool.find_by(name: tool_name)
      assert_not_nil tool, "expected #{tool_name} to be seeded"
      assert_equal "code", tool.source
      assert_equal "app", tool.execution_mode.to_s
      assert tool.enabled?
    end
  end

  test "seed creates the three Coder MCP system tools" do
    Tools::Reconciler.run!

    %w[coder_allocate_machine coder_ssh_exec coder_release_machine].each do |tool_name|
      tool = Tool.find_by(name: tool_name)
      assert_not_nil tool, "expected #{tool_name} to be seeded"
      assert_equal "code", tool.source
      assert_equal "app", tool.execution_mode.to_s
    end
  end

  test "board_add_comment tool description mentions markdown support" do
    Tools::Reconciler.run!

    tool = Tool.find_by(name: "board_add_comment")
    assert_not_nil tool

    assert_match(/markdown/i, tool.description,
      "board_add_comment description should mention markdown support")

    body_schema = tool.input_schema.dig("properties", "body")
    assert_not_nil body_schema
    assert_match(/markdown/i, body_schema["description"],
      "board_add_comment body parameter description should mention markdown")
  end
end
