# frozen_string_literal: true

require "test_helper"

class WorkflowDuplicatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @source = create(:workflow, scope: @company, name: "Source WF")
    @step1 = create(:step, workflow: @source, position: 1, name: "First",
                           tool_ids: [ 7 ], skill_ids: [ 8 ], mcp_server_ids: [ 9 ],
                           asset_ids: [ 42, 43 ])
    @step2 = create(:step, workflow: @source, position: 2, name: "Second",
                           depends_on_step_ids: [ @step1.id ],
                           preferred_model: "claude-sonnet-4",
                           bmad_enabled: true,
                           required_agent_runtime: "claude_code")
    create(:sub_step, step: @step1, name: "Sub 1")
  end

  test "duplicates workflow with steps sub_steps and remapped dependencies" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_equal "Project", copy.scope_type
    assert_equal @project.id, copy.scope_id
    assert_equal 2, copy.steps.not_deleted.count

    copied_steps = copy.steps.not_deleted.order(:position).to_a
    assert_equal [ "First", "Second" ], copied_steps.map(&:name)
    assert_equal copied_steps[0].id, copied_steps[1].depends_on_step_ids.first
    assert_equal "claude-sonnet-4", copied_steps[1].preferred_model
    assert copied_steps[1].bmad_enabled
    assert_equal "claude_code", copied_steps[1].required_agent_runtime
    assert_equal 1, copied_steps[0].sub_steps.active.count
    assert_equal [ 7 ], copied_steps[0].tool_ids
    assert_equal [ 8 ], copied_steps[0].skill_ids
    assert_equal [ 9 ], copied_steps[0].mcp_server_ids
    assert_equal [ 42, 43 ], copied_steps[0].asset_ids
  end

  test "generates unique name when duplicate exists" do
    create(:workflow, scope: @project, name: "Source WF")

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_equal "Source WF (1)", copy.name
  end

  test "uses explicit name when provided" do
    copy = WorkflowDuplicator.new(@source, target_scope: @project, name: "Custom Name").duplicate!

    assert_equal "Custom Name", copy.name
  end

  test "generates unique name when explicit name collides" do
    create(:workflow, scope: @project, name: "Custom Name")

    copy = WorkflowDuplicator.new(@source, target_scope: @project, name: "Custom Name").duplicate!

    assert_equal "Custom Name (1)", copy.name
  end
end
