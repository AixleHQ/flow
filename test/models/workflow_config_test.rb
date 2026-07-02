# frozen_string_literal: true

require "test_helper"

class WorkflowConfigTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @workflow = create(:workflow, :with_company_scope, config: {})
  end

  test "base_tool_ids returns empty array by default" do
    assert_equal [], @workflow.base_tool_ids
  end

  test "base_skill_ids returns empty array by default" do
    assert_equal [], @workflow.base_skill_ids
  end

  test "base_mcp_server_ids returns empty array by default" do
    assert_equal [], @workflow.base_mcp_server_ids
  end

  test "base_asset_ids returns empty array by default" do
    assert_equal [], @workflow.base_asset_ids
  end

  test "inherit_all_project_resources returns false by default" do
    refute @workflow.inherit_all_project_resources
  end

  test "config round-trip preserves base_tool_ids" do
    @workflow.update!(config: { "base_tool_ids" => [ 1, 2 ] })
    @workflow.reload

    assert_equal [ 1, 2 ], @workflow.base_tool_ids
  end

  test "merge_config! merges without overwriting other keys" do
    @workflow.update!(config: { "base_tool_ids" => [ 1 ], "base_skill_ids" => [ 10 ] })
    @workflow.merge_config!("base_tool_ids" => [ 1, 2, 3 ])
    @workflow.reload

    assert_equal [ 1, 2, 3 ], @workflow.base_tool_ids
    assert_equal [ 10 ], @workflow.base_skill_ids
  end

  test "merge_config! sets inherit_all_project_resources" do
    @workflow.merge_config!("inherit_all_project_resources" => true)
    @workflow.reload

    assert @workflow.inherit_all_project_resources
  end

  test "empty config returns safe defaults" do
    @workflow.update!(config: {})
    @workflow.reload

    assert_equal [], @workflow.base_tool_ids
    assert_equal [], @workflow.base_skill_ids
    assert_equal [], @workflow.base_mcp_server_ids
    assert_equal [], @workflow.base_asset_ids
    refute @workflow.inherit_all_project_resources
  end
end
