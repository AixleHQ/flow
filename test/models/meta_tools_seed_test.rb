# frozen_string_literal: true

require "test_helper"

class MetaToolsSeedTest < ActiveSupport::TestCase
  AIXLE_BUILDER_TOOL_NAMES = %w[
    meta_create_workflow meta_create_agent meta_create_step
    meta_create_sub_step meta_update_sub_step meta_delete_sub_step
    meta_get_workflow meta_list_workflows
    meta_finalize_workflow meta_update_step meta_delete_step
    meta_reorder_steps meta_create_tool meta_install_skill
    meta_search_skills meta_create_mcp_server meta_link_resource_to_step
    meta_list_agents meta_list_tools meta_list_skills
    meta_get_board meta_create_board_column meta_update_board_column
    meta_delete_board_column meta_reorder_board_columns
    meta_create_column_binding meta_update_column_binding
    meta_delete_column_binding meta_setup_board_from_preset
    meta_delete_workflow
  ].freeze

  setup do
    Tools::Reconciler.run!
  end

  test "all 30 aixle builder tool names exist as platform tools" do
    found = Tool.code_source.where(name: AIXLE_BUILDER_TOOL_NAMES).pluck(:name).sort
    assert_equal AIXLE_BUILDER_TOOL_NAMES.sort, found,
      "Missing tools: #{(AIXLE_BUILDER_TOOL_NAMES - found).inspect}"
  end

  test "all seeded tools have a valid input_schema with type key" do
    tools = Tool.code_source.where(name: AIXLE_BUILDER_TOOL_NAMES)
    tools.each do |tool|
      assert_not_nil tool.input_schema, "#{tool.name} has nil input_schema"
      assert tool.input_schema.key?("type"), "#{tool.name} input_schema missing 'type' key"
    end
  end

  test "every meta service file has a corresponding seeded tool" do
    meta_service_dir = Rails.root.join("app/services/internal_tools")
    service_names = Dir[meta_service_dir.join("meta_*.rb")]
                      .map { |f| File.basename(f, ".rb") }
                      .reject { |n| n == "meta_tool_helpers" }

    seeded_names = Tool.code_source.where("tools.tags @> ?", %w[builder].to_json).pluck(:name)

    service_names.each do |service_name|
      assert_includes seeded_names, service_name,
        "Service #{service_name}.rb exists but no matching tool is seeded"
    end
  end
end
