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

  test "only group-presentation catalog tags appear" do
    tags = Tools::PickerGroups.for_project(@project).map { |g| g[:tag] }
    assert_includes tags, "board"
    assert_not_includes tags, "messaging"  # visible but individual, not a group
    assert_not_includes tags, "builder"    # hidden
  end
end
