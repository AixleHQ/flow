# frozen_string_literal: true

require "test_helper"

class ContextBuilders::ConfigItemsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user    = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project,
                                                         mode: "interactive")
  end

  def build_section
    ContextBuilders::ConfigItems.new(@session.reload).build.first
  end

  test "not applicable when nothing is attached" do
    create(:config_item, :secret, scope: @project, name: "UNATTACHED")

    assert_not ContextBuilders::ConfigItems.new(@session).applicable?
  end

  test "applicable once an item is attached" do
    @session.config_items << create(:config_item, :variable, scope: @project, name: "API_BASE")

    assert ContextBuilders::ConfigItems.new(@session.reload).applicable?
  end

  test "lists names and types and never the value" do
    @session.config_items << create(:config_item, :secret, scope: @project, name: "STRIPE_KEY",
                                                          value: "sk_live_abc123",
                                                          description: "Billing API key")
    @session.config_items << create(:config_item, :variable, scope: @project, name: "API_BASE",
                                                            value: "https://api.test")

    section = build_section

    assert_equal "available-config-items", section.tag
    assert_includes section.content, "STRIPE_KEY"
    assert_includes section.content, "API_BASE"
    assert_includes section.content, "Billing API key"
    assert_includes section.content, "get_config_item"
    # The whole point of fetching on demand: no value in the context file, which
    # is written into the container and echoed into context.log.
    assert_not_includes section.content, "sk_live_abc123"
    assert_not_includes section.content, "https://api.test"
  end

  test "adds the handling warning only when a secret is attached" do
    @session.config_items << create(:config_item, :variable, scope: @project, name: "API_BASE")

    assert_not_includes build_section.content, "do not echo it"

    @session.config_items << create(:config_item, :secret, scope: @project, name: "STRIPE_KEY")

    assert_includes build_section.content, "do not echo it"
  end

  test "resolves items attached through the workflow and step cascade" do
    item = create(:config_item, :secret, scope: @project, name: "STEP_KEY")
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, config_item_ids: [ item.id ])
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @session.update!(session_type: "workflow_step")
    create(:step_run, workflow_run: workflow_run, step: step, terminal_session: @session)

    assert_includes build_section.content, "STEP_KEY"
  end
end
