# frozen_string_literal: true

require "test_helper"

class ContextBuilders::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "build includes outputs directory always" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    sections = ContextBuilders::Workspace.new(session).build
    assert_equal 1, sections.length
    assert_equal "workspace", sections.first.tag
    assert_equal :important, sections.first.priority
    assert_includes sections.first.content, "/workspace/outputs/"
  end

  test "build includes assets directory when input_asset_ids present" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    session.input_assets << asset

    sections = ContextBuilders::Workspace.new(session.reload).build
    assert_includes sections.first.content, "/workspace/assets/"
    assert_includes sections.first.content, "Read-only"
  end

  test "build excludes assets directory when no input_asset_ids" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    sections = ContextBuilders::Workspace.new(session).build
    assert_not_includes sections.first.content, "/workspace/assets/"
  end
end
