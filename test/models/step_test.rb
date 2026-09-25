# frozen_string_literal: true

require "test_helper"

class StepTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
    @workflow = create(:workflow, scope: @project)
  end

  test "valid with required attributes" do
    step = build(:step, workflow: @workflow, position: 1)
    assert step.valid?
  end

  test "invalid without name" do
    step = build(:step, workflow: @workflow, name: nil)
    assert_not step.valid?
  end

  test "a new step without a position is appended rather than rejected" do
    create(:step, workflow: @workflow, position: 4)

    step = create(:step, workflow: @workflow, position: nil)

    assert_equal 5, step.position
  end

  # Soft-deleted steps keep their position and the unique (workflow, position)
  # index still covers them, so the next free number cannot be read off the
  # visible list — which is how the builder kept colliding with a step the user
  # had already deleted.
  test "the appended position clears soft-deleted steps too" do
    create(:step, workflow: @workflow, position: 1)
    deleted = create(:step, workflow: @workflow, position: 2)
    deleted.soft_delete!

    step = create(:step, workflow: @workflow, position: nil)

    assert_equal 3, step.position, "position 2 is still taken by the deleted step's row"
    # The client cannot see the row it has to skip — which is the whole point.
    assert_equal [ 1, 3 ], @workflow.steps.not_deleted.pluck(:position)
  end

  test "position cannot be cleared once the step exists" do
    step = create(:step, workflow: @workflow, position: 1)

    assert_not step.update(position: nil)
  end

  test "unique position per workflow" do
    create(:step, workflow: @workflow, position: 1)
    duplicate = build(:step, workflow: @workflow, position: 1)
    assert_not duplicate.valid?
  end

  test "same position in different workflows" do
    other = create(:workflow, scope: @project)
    create(:step, workflow: @workflow, position: 1)
    step = build(:step, workflow: other, position: 1)
    assert step.valid?
  end

  test "ordered by position by default" do
    create(:step, workflow: @workflow, position: 3, name: "Third")
    create(:step, workflow: @workflow, position: 1, name: "First")
    create(:step, workflow: @workflow, position: 2, name: "Second")
    names = @workflow.steps.pluck(:name)
    assert_equal %w[First Second Third], names
  end

  test "enumerize skip_policy" do
    step = build(:step, workflow: @workflow, skip_policy: :manual)
    assert_equal "manual", step.skip_policy
  end

  test "enumerize on_failure" do
    step = build(:step, workflow: @workflow, on_failure: :retry)
    assert_equal "retry", step.on_failure
  end

  test "agent is optional" do
    step = build(:step, workflow: @workflow, agent: nil)
    assert step.valid?
  end

  test "nested sub_steps via accepts_nested_attributes" do
    step = create(:step, workflow: @workflow, position: 1, sub_steps_attributes: [
      { name: "Sub 1", position: 1 },
      { name: "Sub 2", position: 2 }
    ])
    assert_equal 2, step.sub_steps.count
  end

  test "destroy soft-deletes a step that never ran, keeping its id and sub-steps" do
    step = create(:step, workflow: @workflow, position: 1)
    sub = create(:sub_step, step: step, position: 1)

    assert_no_difference [ "Step.count", "SubStep.count" ] do
      step.destroy
    end
    assert step.reload.deleted?
    assert_equal step, sub.reload.step
  end

  test "steps that would wait on each other are rejected, naming the cycle" do
    build_step = create(:step, workflow: @workflow, name: "Build", position: 1)
    test_step = create(:step, workflow: @workflow, name: "Test", position: 2, depends_on_step_ids: [ build_step.id ])

    assert_not build_step.update(depends_on_step_ids: [ test_step.id ])
    assert_includes build_step.errors[:depends_on_step_ids], "would create a cycle: Build → Test → Build"
  end

  test "a longer cycle is rejected too" do
    first = create(:step, workflow: @workflow, name: "First", position: 1)
    second = create(:step, workflow: @workflow, name: "Second", position: 2, depends_on_step_ids: [ first.id ])
    third = create(:step, workflow: @workflow, name: "Third", position: 3, depends_on_step_ids: [ second.id ])

    assert_not first.update(depends_on_step_ids: [ third.id ])
    assert_includes first.errors[:depends_on_step_ids], "would create a cycle: First → Third → Second → First"
  end

  test "a diamond is not a cycle" do
    root = create(:step, workflow: @workflow, name: "Root", position: 1)
    left = create(:step, workflow: @workflow, name: "Left", position: 2, depends_on_step_ids: [ root.id ])
    right = create(:step, workflow: @workflow, name: "Right", position: 3, depends_on_step_ids: [ root.id ])

    assert create(:step, workflow: @workflow, name: "Join", position: 4, depends_on_step_ids: [ left.id, right.id ]).valid?
    assert right.update(depends_on_step_ids: [ root.id, left.id ])
  end

  test "destroy returns false when another active step depends on it" do
    step_a = create(:step, workflow: @workflow, position: 1)
    create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [ step_a.id ])

    result = step_a.destroy
    refute result
    assert step_a.errors[:base].any?
    assert Step.exists?(step_a.id)
  end

  test "destroy succeeds when dependent step is already soft-deleted" do
    step_a = create(:step, workflow: @workflow, position: 1)
    step_b = create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [ step_a.id ])
    step_b.soft_delete!

    step_a.destroy
    assert step_a.reload.deleted?
  end

  test "rejects agents, tools, MCP servers and repositories of another project" do
    other = create(:project, :standalone)
    step = build(:step, workflow: @workflow,
                        agent: create(:agent, scope: other),
                        tool_ids: [ create(:tool, scope: other).id ],
                        mcp_server_ids: [ create(:mcp_server, scope: other).id ],
                        repository_ids: [ create(:repository, scope: other).id ])

    assert_not step.valid?
    assert_equal %i[agent_id mcp_server_ids repository_ids tool_ids], step.errors.attribute_names.sort
  end

  test "accepts own resources and platform tools" do
    platform_tool = create(:tool, :system)
    step = build(:step, workflow: @workflow,
                        agent: create(:agent, scope: @project),
                        tool_ids: [ create(:tool, scope: @project).id, platform_tool.id ],
                        asset_ids: [ create(:asset, scope: @company).id ])

    assert step.valid?, step.errors.full_messages.to_sentence
  end

  test "a stale foreign id already on the step does not block unrelated edits" do
    step = create(:step, workflow: @workflow)
    step.update_column(:mcp_server_ids, [ create(:mcp_server, scope: create(:project, :standalone)).id ])

    assert step.reload.update(name: "Renamed"), step.errors.full_messages.to_sentence
  end
end
