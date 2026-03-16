# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seeds/platform_tools")

class Seeds::PlatformToolsTest < ActiveSupport::TestCase
  test "seed creates board workflow tools" do
    Seeds::PlatformTools.seed!

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
    ].each do |tool_name|
      tool = Tool.find_by(name: tool_name)
      assert_not_nil tool, "expected #{tool_name} to be seeded"
      assert_equal "workflow", tool.kind.to_s
      assert_equal "app", tool.execution_mode.to_s
      assert tool.enabled?
    end
  end
end
