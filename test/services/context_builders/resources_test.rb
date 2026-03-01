# frozen_string_literal: true

require "test_helper"

class ContextBuilders::ResourcesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "applicable returns false when no repos assets or skills" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    builder = ContextBuilders::Resources.new(session)
    assert_not builder.applicable?
  end

  test "applicable returns true with input assets" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    session.input_assets << asset

    builder = ContextBuilders::Resources.new(session.reload)
    assert builder.applicable?
  end

  test "build returns available-resources section" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")
    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    session.input_assets << asset

    sections = ContextBuilders::Resources.new(session.reload).build
    assert_equal 1, sections.length
    assert_equal "available-resources", sections.first.tag
    assert_equal :info, sections.first.priority
  end
end
