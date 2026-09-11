# frozen_string_literal: true

require "test_helper"

class Tools::PickerGroupsTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
    Tools::Reconciler.run!
  end

  test "board group resolves to the project's board tool ids" do
    groups = Tools::PickerGroups.for_project(@project)
    board = groups.find { |g| g[:tag] == "board" }

    assert_equal "Board management", board[:label]
    expected = Tool.visible_for_project(@project).select { |t| t.tags.include?("board") }.map(&:id).sort
    assert_equal expected, board[:tool_ids].sort
    assert expected.any?
  end

  test "only visible catalog tags appear" do
    tags = Tools::PickerGroups.for_project(@project).map { |g| g[:tag] }

    assert_includes tags, "board"
    assert_not_includes tags, "messaging" # umbrella over :slack, hidden
    assert_not_includes tags, "builder"   # hidden
  end

  test "a group whose tools this project cannot see is dropped" do
    # Slack tools are gated on the integration, so an unconnected project must
    # not be offered an empty "Slack" entry.
    assert_not_includes Tools::PickerGroups.for_project(@project).map { |g| g[:tag] }, "slack"

    create(:integration, :active, provider: :slack, project: @project, company: @project.company)
    slack = Tools::PickerGroups.for_project(@project).find { |g| g[:tag] == "slack" }

    assert_equal "Slack", slack[:label]
    expected = Tool.visible_for_project(@project).select { |t| t.tags.include?("slack") }.map(&:id).sort
    assert_equal expected, slack[:tool_ids].sort
    assert expected.any?
  end
end
