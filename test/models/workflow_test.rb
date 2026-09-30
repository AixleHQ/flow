# frozen_string_literal: true

require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
  end

  test "valid with required attributes" do
    workflow = build(:workflow, scope: @project)
    assert workflow.valid?
  end

  test "company scope is rejected (workflows are project- or system-scoped)" do
    workflow = build(:workflow, scope: @company)
    assert_not workflow.valid?
    assert_includes workflow.errors[:scope_type], "is not included in the list"
  end

  test "invalid without name" do
    workflow = build(:workflow, scope: @project, name: nil)
    assert_not workflow.valid?
    assert_includes workflow.errors[:name], "can't be blank"
  end

  test "invalid without scope" do
    workflow = build(:workflow, scope: nil)
    assert_not workflow.valid?
  end

  test "unique name per scope" do
    create(:workflow, name: "deploy", scope: @project)
    duplicate = build(:workflow, name: "deploy", scope: @project)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "same name allowed in different scopes" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, name: "deploy", scope: @project)
    other_workflow = build(:workflow, name: "deploy", scope: project2)
    assert other_workflow.valid?
  end

  test "soft-deleted workflow name can be reused" do
    old = create(:workflow, name: "deploy", scope: @project)
    old.soft_delete!
    new_wf = build(:workflow, name: "deploy", scope: @project)
    assert new_wf.valid?
  end

  test "belonging_to_company scope returns workflows of all company projects" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, scope: @project)
    create(:workflow, scope: project2)
    assert_equal 2, Workflow.belonging_to_company(@company).count
  end

  test "for_project scope" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, scope: @project)
    create(:workflow, scope: project2)
    assert_equal 1, Workflow.for_project(@project).count
  end

  test "visible_for_project returns only that project's workflows" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    mine = create(:workflow, name: "deploy", scope: @project)
    other = create(:workflow, name: "ci", scope: project2)
    merged = Workflow.visible_for_project(@project)
    assert_includes merged, mine
    refute_includes merged, other
  end

  test "visible_for_project excludes deleted workflows" do
    wf = create(:workflow, scope: @project)
    wf.soft_delete!
    assert_empty Workflow.visible_for_project(@project)
  end

  test "active scope excludes deleted" do
    wf = create(:workflow, scope: @project)
    wf.soft_delete!
    assert_not_includes Workflow.active, wf
  end

  test "scope_indicator returns system or project" do
    assert_equal "system", build(:workflow, :system).scope_indicator
    assert_equal "project", build(:workflow, scope: @project).scope_indicator
  end

  # Deleting a workflow must stop everything that could start it again.
  test "soft_delete switches its triggers off and they no longer match events" do
    wf = create(:workflow, scope: @project)
    user = create(:user, company: @project.company)
    binding = create(:trigger_binding, project: @project, workflow: wf, created_by: user, event_type: "webhook.received")
    event = create(:trigger_event, event_type: "webhook.received", project: @project)
    assert_includes TriggerBinding.for_event(event), binding

    wf.soft_delete!

    assert_not binding.reload.enabled
    assert_not binding.live?
    assert_not_includes TriggerBinding.for_event(event), binding
  end

  test "soft_delete is refused while a run is live" do
    wf = create(:workflow, scope: @project)
    create(:workflow_run, :running, workflow: wf, project: @project, user: create(:user, company: @project.company))

    assert_raises(ActiveRecord::RecordNotDestroyed) { wf.soft_delete! }
    assert_nil wf.reload.deleted_at
  end

  test "soft_delete sets deleted_at" do
    wf = create(:workflow, scope: @project)
    assert_nil wf.deleted_at
    wf.soft_delete!
    assert_not_nil wf.reload.deleted_at
  end

  test "soft_delete! raises when the workflow is still bound to a board column" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    wf = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: column, workflow: wf, trigger_mode: :manual)

    assert_raises(ActiveRecord::RecordNotDestroyed) { wf.soft_delete! }
    assert_nil wf.reload.deleted_at
  end

  test "destroy aborts when the workflow is still bound to a board column" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    wf = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: column, workflow: wf, trigger_mode: :manual)

    assert_not wf.destroy
    assert Workflow.exists?(wf.id)
    assert_includes wf.errors[:base].join, "Cannot delete — bound to column"
  end

  test "config defaults to empty hash" do
    wf = create(:workflow, scope: @project)
    assert_equal({}, wf.config)
  end

  test "visible_steps drops soft-deleted steps in position order" do
    wf = create(:workflow, scope: @project)
    first = create(:step, workflow: wf, position: 1)
    create(:step, workflow: wf, position: 2).soft_delete!
    third = create(:step, workflow: wf, position: 3)

    assert_equal [ first.id, third.id ], wf.reload.visible_steps.map(&:id)
  end

  test "visible_steps reads a preloaded association instead of re-querying it" do
    wf = create(:workflow, scope: @project)
    kept = create(:step, workflow: wf, position: 1)
    create(:step, workflow: wf, position: 2).soft_delete!
    create(:sub_step, step: kept)

    preloaded = Workflow.where(id: wf.id).includes(steps: :sub_steps).first

    assert_no_queries do
      assert_equal [ kept.id ], preloaded.visible_steps.map(&:id)
      assert_equal 1, preloaded.visible_steps.first.sub_steps.size
    end
  end

  test "rejects base resource ids of another project" do
    other = create(:project, :standalone)
    workflow = build(:workflow, scope: @project,
                                config: { "base_mcp_server_ids" => [ create(:mcp_server, scope: other).id ],
                                          "base_skill_ids" => [ create(:skill, scope: @project).id ] })

    assert_not workflow.valid?
    assert_match(/base_mcp_server_ids contains ids outside this project/, workflow.errors[:config].to_sentence)
  end

  test "attach_run_stats reports count, latest run, and active runs in one query" do
    busy = create(:workflow, scope: @project)
    quiet = create(:workflow, scope: @project)
    untouched = create(:workflow, scope: @project)
    create(:workflow_run, workflow: busy, state: "paused").update_columns(created_at: 3.days.ago)
    create(:workflow_run, :completed, workflow: busy).update_columns(created_at: 2.days.ago)
    latest = create(:workflow_run, :running, workflow: busy)
    latest.update_columns(created_at: 1.hour.ago)
    create(:workflow_run, :completed, workflow: quiet).update_columns(created_at: 5.days.ago)

    listed = Workflow.where(id: [ busy.id, quiet.id, untouched.id ]).to_a
    stats = nil
    assert_queries_count(1) do
      stats = Workflow.attach_run_stats(listed).index_by(&:id)
    end

    assert_equal 3, stats[busy.id].run_stats.count
    assert_equal "running", stats[busy.id].run_stats.last_state
    assert_in_delta latest.reload.created_at, stats[busy.id].run_stats.last_at, 1
    assert stats[busy.id].run_stats.active

    assert_equal 1, stats[quiet.id].run_stats.count
    assert_equal "completed", stats[quiet.id].run_stats.last_state
    refute stats[quiet.id].run_stats.active

    assert_equal 0, stats[untouched.id].run_stats.count
    assert_nil stats[untouched.id].run_stats.last_at
    assert_nil stats[untouched.id].run_stats.last_state
    refute stats[untouched.id].run_stats.active
  end

  test "attach_run_stats breaks a created_at tie toward the higher id" do
    workflow = create(:workflow, scope: @project)
    stamp = Time.zone.parse("2026-03-01 12:00:00")
    create(:workflow_run, :completed, workflow: workflow).update_columns(created_at: stamp)
    later = create(:workflow_run, :failed, workflow: workflow)
    later.update_columns(created_at: stamp)

    stats = Workflow.attach_run_stats([ workflow.reload ]).first.run_stats

    assert_operator later.id, :>, workflow.runs.minimum(:id)
    assert_equal "failed", stats.last_state
  end

  test "run_stats loads a single workflow once and then reads the cache" do
    workflow = create(:workflow, scope: @project)
    create(:workflow_run, :running, workflow: workflow)
    loaded = Workflow.find(workflow.id)

    assert_queries_count(1) { assert_equal "running", loaded.run_stats.last_state }
    assert_no_queries { assert_equal 1, loaded.run_stats.count }
  end
end
