# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaReorderStepsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    # Builder workflow context (simulating Aixle Builder running)
    builder_workflow = create(:workflow, scope: @project)
    builder_step = create(:step, workflow: builder_workflow)
    @workflow_run = create(:workflow_run, workflow: builder_workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: builder_step)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  test "reorders steps by explicit workflow_id and persists new positions" do
    wf = create(:workflow, scope: @project, name: "Target WF")
    # Seed initial positions in a high block so the reorder's target range (1..N)
    # never collides with an existing position mid-update.
    step_a = create(:step, workflow: wf, name: "A", position: 101)
    step_b = create(:step, workflow: wf, name: "B", position: 102)
    step_c = create(:step, workflow: wf, name: "C", position: 103)

    new_order = [ step_c.id, step_a.id, step_b.id ]

    result = InternalTools::MetaReorderSteps.new(
      params: { workflow_id: wf.id, step_ids: new_order },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_empty result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal wf.id, data["workflow_id"]
    assert_equal new_order, data["new_order"]

    # Positions rewritten to match the supplied order (1-indexed)
    assert_equal 1, step_c.reload.position
    assert_equal 2, step_a.reload.position
    assert_equal 3, step_b.reload.position
  end

  test "reorders steps using target workflow from shared_context" do
    wf = create(:workflow, scope: @project, name: "Context WF")
    # High initial positions so the reorder's target range (1..N) never collides.
    step_one = create(:step, workflow: wf, name: "One", position: 101)
    step_two = create(:step, workflow: wf, name: "Two", position: 102)
    @workflow_run.update!(shared_context: { "target_workflow_id" => wf.id })

    result = InternalTools::MetaReorderSteps.new(
      params: { step_ids: [ step_two.id, step_one.id ] },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal wf.id, data["workflow_id"]
    assert_equal [ step_two.id, step_one.id ], data["new_order"]

    assert_equal 1, step_two.reload.position
    assert_equal 2, step_one.reload.position
  end

  test "reordering the steps' loaded order reflects the new positions" do
    wf = create(:workflow, scope: @project, name: "Ordered WF")
    # High initial positions so the reorder's target range (1..N) never collides.
    step_x = create(:step, workflow: wf, name: "X", position: 101)
    step_y = create(:step, workflow: wf, name: "Y", position: 102)
    step_z = create(:step, workflow: wf, name: "Z", position: 103)

    result = InternalTools::MetaReorderSteps.new(
      params: { workflow_id: wf.id, step_ids: [ step_z.id, step_y.id, step_x.id ] },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]

    # Step has default_scope { order(:position) }, so a fresh load reflects the new order
    assert_equal [ step_z.id, step_y.id, step_x.id ], wf.steps.reload.map(&:id)
  end
end
