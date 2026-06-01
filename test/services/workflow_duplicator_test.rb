# frozen_string_literal: true

require "test_helper"

class WorkflowDuplicatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @source = create(:workflow, scope: @company, name: "Source WF")
    @step1 = create(:step, workflow: @source, position: 1, name: "First")
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
    assert_equal "standard", copy.kind
    assert_equal 2, copy.steps.not_deleted.count

    copied_steps = copy.steps.not_deleted.order(:position).to_a
    assert_equal [ "First", "Second" ], copied_steps.map(&:name)
    assert_equal copied_steps[0].id, copied_steps[1].depends_on_step_ids.first
    assert_equal "claude-sonnet-4", copied_steps[1].preferred_model
    assert copied_steps[1].bmad_enabled
    assert_equal "claude_code", copied_steps[1].required_agent_runtime
    assert_equal 1, copied_steps[0].sub_steps.active.count
  end

  test "generates unique name when duplicate exists" do
    create(:workflow, scope: @project, name: "Source WF")

    copy = WorkflowDuplicator.new(@source, target_scope: @project).duplicate!

    assert_equal "Source WF (1)", copy.name
  end

  test "generates unique name when explicit name collides" do
    create(:workflow, scope: @project, name: "Custom Name")

    copy = WorkflowDuplicator.new(@source, target_scope: @project, name: "Custom Name").duplicate!

    assert_equal "Custom Name (1)", copy.name
  end

  test "supports template_snapshot kind" do
    copy = WorkflowDuplicator.new(@source, target_scope: @company, kind: "template_snapshot").duplicate!

    assert_equal "template_snapshot", copy.kind
    assert_equal "Company", copy.scope_type
  end
end
