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
    assert_not_includes tags, "messaging" # umbrella over :chat, hidden
    assert_not_includes tags, "builder"   # hidden
  end

  test "a group whose tools this project cannot see is dropped" do
    # Chat tools are gated on a messenger being connected, so an unconnected
    # project must not be offered an empty "Chat" entry.
    assert_not_includes Tools::PickerGroups.for_project(@project).map { |g| g[:tag] }, "chat"

    create(:integration, :active, provider: :slack, project: @project, company: @project.company)
    chat = Tools::PickerGroups.for_project(@project).find { |g| g[:tag] == "chat" }

    assert_equal "Chat (Slack and Teams)", chat[:label]
    expected = Tool.visible_for_project(@project).select { |t| t.tags.include?("chat") }.map(&:id).sort
    assert_equal expected, chat[:tool_ids].sort
    assert expected.any?
  end
end
