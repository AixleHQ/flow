# frozen_string_literal: true

require "test_helper"

class ContextBuilders::BaseTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, mode: "interactive")
  end

  test "applicable? returns true by default" do
    builder = ContextBuilders::Base.new(@session)
    assert builder.applicable?
  end

  test "build raises NotImplementedError" do
    builder = ContextBuilders::Base.new(@session)
    assert_raises(NotImplementedError) { builder.build }
  end

  test "name returns underscored demodulized class name" do
    builder = ContextBuilders::CriticalRules.new(@session)
    assert_equal "critical_rules", builder.name
  end

  test "section helper auto-fills builder_name" do
    builder = ContextBuilders::CriticalRules.new(@session)
    @session.update_column(:mode, "non_interactive")
    sections = builder.build
    next unless sections.any?

    assert_equal "critical_rules", sections.first.builder_name
  end

  test "navigation helpers return nil safely for standalone session" do
    builder = ContextBuilders::Base.new(@session)
    assert_equal @project, builder.send(:project)
    assert_nil builder.send(:step_run)
    assert_nil builder.send(:workflow_run)
    assert_nil builder.send(:workflow)
    assert_nil builder.send(:board_task)
    assert_nil builder.send(:step)
  end
end
