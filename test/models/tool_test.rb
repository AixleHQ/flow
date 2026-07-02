# frozen_string_literal: true

require "test_helper"

class ToolTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
  end

  def gated_tool
    Tool.create!(name: "slack_post_message", display_name: "Slack Post Message",
      kind: "workflow", source: "code", execution_mode: "app",
      enabled: true, requires_integration: "slack", input_schema: {})
  end

  test "visible_for_project hides an integration-gated tool when the integration is not active" do
    tool = gated_tool
    assert_not_includes Tool.visible_for_project(@project).pluck(:id), tool.id
  end

  test "visible_for_project shows an integration-gated tool once the integration is active" do
    tool = gated_tool
    create(:integration, company: @company, project: @project, provider: :slack,
      status: :active, connected_by: @user)

    assert_includes Tool.visible_for_project(@project).pluck(:id), tool.id
  end

  test "an inactive integration does not unlock a gated tool" do
    tool = gated_tool
    create(:integration, company: @company, project: @project, provider: :slack,
      status: :inactive, connected_by: @user)

    assert_not_includes Tool.visible_for_project(@project).pluck(:id), tool.id
  end

  test "ungated platform tools are always visible" do
    tool = Tool.create!(name: "board_list_tasks", display_name: "Board List Tasks",
      kind: "workflow", source: "code", execution_mode: "app", enabled: true, input_schema: {})

    assert_includes Tool.visible_for_project(@project).pluck(:id), tool.id
  end

  test "visible_for_project hides meta tools even though they are persisted" do
    tool = Tool.create!(name: "meta_create_workflow", display_name: "Meta Create Workflow",
      kind: "meta", source: "code", user_attachable: false, execution_mode: "app", enabled: true, input_schema: {})

    assert tool.persisted?
    assert_not_includes Tool.visible_for_project(@project).pluck(:id), tool.id
  end

  # ── platform-namespace protection (code-first registry) ──

  test "custom tool cannot claim a platform tool name" do
    company = create(:company)
    tool = build(:tool, name: "slack_post_message", scope: company)

    assert_not tool.valid?
    assert_match(/collides with the platform tool/, tool.errors[:name].first)
  end

  test "custom tool cannot use the reserved mcp__ namespace" do
    company = create(:company)
    tool = build(:tool, name: "mcp__coder_1__coder_ssh_exec", scope: company)

    assert_not tool.valid?
    assert_match(/reserved mcp__ namespace/, tool.errors[:name].first)
  end

  test "reconciler-owned code rows are exempt from the namespace validation" do
    row = build(:tool, :meta, name: "meta_create_tool", source: "code")

    assert row.valid?, row.errors.full_messages.to_sentence
  end
end
