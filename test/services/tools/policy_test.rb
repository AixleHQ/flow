# frozen_string_literal: true

require "test_helper"

class Tools::PolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @other = create(:company)
  end

  test "tools are allowed by default with zero flag ceremony" do
    assert Tools::Policy.allowed?("slack_post_message", @company)
    assert Tools::Policy.allowed?("slack_post_message", nil)
  end

  test "global kill switch pulls the tool for everyone" do
    Tools::Policy.kill!("board_list_tasks")

    assert_not Tools::Policy.allowed?("board_list_tasks", @company)
    assert_not Tools::Policy.allowed?("board_list_tasks", @other)

    Tools::Policy.revive!("board_list_tasks")
    assert Tools::Policy.allowed?("board_list_tasks", @company)
  end

  test "per-company kill switch pulls the tool for that company only" do
    Tools::Policy.kill!("board_list_tasks", company: @company)

    assert_not Tools::Policy.allowed?("board_list_tasks", @company)
    assert Tools::Policy.allowed?("board_list_tasks", @other)
  end

  test "an existing rollout flag gates the tool to enabled companies" do
    Flipper.add("tool_rollout__new_shiny_tool")

    assert_not Tools::Policy.allowed?("new_shiny_tool", @company)

    Flipper.enable_actor("tool_rollout__new_shiny_tool", @company)
    assert Tools::Policy.allowed?("new_shiny_tool", @company)
    assert_not Tools::Policy.allowed?("new_shiny_tool", @other)
  end

  test "a killed tool disappears from availability" do
    user = create(:user, company: @company)
    project = create(:project, company: @company, owner: user)
    Tools::Reconciler.run!
    tool = Tool.code_source.find_by!(name: "board_list_tasks")
    ctx = Tools::Context.new(project: project, company: @company)

    assert tool.available?(ctx)
    Tools::Policy.kill!("board_list_tasks", company: @company)
    assert_not tool.available?(ctx)
  end
end
