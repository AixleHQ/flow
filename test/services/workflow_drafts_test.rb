# frozen_string_literal: true

require "test_helper"

class WorkflowDraftsTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @actor = Versions::Actor.ui(@user)
    @project = create(:project, :standalone)
    @tool = create(:tool, scope: @project)
    @repository = create(:repository, scope: @project)
    @workflow = create(:workflow, scope: @project, name: "Release", config: { "base_repository_ids" => [ @repository.id ] })
    @build = create(:step, workflow: @workflow, name: "Build", position: 1, tool_ids: [ @tool.id ])
    @test = create(:step, workflow: @workflow, name: "Test", position: 2, depends_on_step_ids: [ @build.id ],
                          instructions: "Check {{output:#{@build.id}:build.log}} from {{step:#{@build.id}}}")
    @lint = create(:sub_step, step: @build, name: "lint", position: 1)
  end

  # The builder's Save on the draft: its steps as WorkflowAggregateSave takes them.
  def save_draft(draft, steps, **fields)
    payload = { "name" => draft.name, **fields.stringify_keys, "steps" => steps }
    Versions.save!(draft, actor: @actor) { WorkflowAggregateSave.new(draft, payload).validate!.apply! }
    draft.reload
  end

  def draft_step(draft, name)
    draft.steps.not_deleted.find_by!(name: name)
  end

  test "a draft is a hidden copy that remembers which step each of its steps came from" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)

    build = draft_step(draft, "Build")
    test = draft_step(draft, "Test")
    assert_equal [ @workflow, "Release", @workflow.current_version_number ],
                 [ draft.draft_of, draft.name, draft.draft_base_version ]
    assert_equal [ @build.id, @test.id ], [ build.origin_step_id, test.origin_step_id ]
    assert_equal [ build.id ], test.depends_on_step_ids
    assert_equal "Check {{output:#{build.id}:build.log}} from {{step:#{build.id}}}", test.instructions
    assert_equal [ @tool.id ], build.tool_ids
    assert_equal [ @lint.id ], build.sub_steps.map(&:origin_sub_step_id)
    assert_equal [ @repository.id ], draft.base_repository_ids
    assert_equal [ @workflow ], Workflow.visible_for_project(@project).to_a
    assert_includes Workflow.editable_for_project(@project), draft
    assert_equal draft, WorkflowDrafts.open!(@workflow, actor: @actor), "a second open returns the open draft"
  end

  test "applying a draft writes it onto the original's own rows as one version and closes it" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    build = draft_step(draft, "Build")
    test = draft_step(draft, "Test")
    lint = build.sub_steps.first
    save_draft(draft, [
      { "id" => build.id, "name" => "Compile", "instructions" => "make",
        "sub_steps" => [ { "id" => lint.id, "name" => "lint --strict" }, { "name" => "format" } ] },
      { "key" => "new-1", "name" => "Package", "depends_on_step_ids" => [ build.id ],
        "instructions" => "Ship {{step:#{build.id}}}" },
      { "id" => test.id, "name" => "Test", "depends_on_step_ids" => [ "new-1" ],
        "instructions" => "Test {{output:new-1:pkg.tgz}}" }
    ], "description" => "faster")
    package = draft_step(draft, "Package")
    save_draft(draft, [
      { "id" => build.id, "name" => "Compile", "instructions" => "make",
        "sub_steps" => build.reload.sub_steps.active.order(:position).map { |s| { "id" => s.id, "name" => s.name } } },
      { "id" => package.id, "name" => "Package", "depends_on_step_ids" => [ build.id ],
        "instructions" => "Ship {{step:#{build.id}}}" }
    ])

    version = WorkflowDrafts.apply!(draft, actor: @actor)

    @workflow.reload
    live_package = @workflow.steps.not_deleted.find_by!(name: "Package")
    assert_equal [ @build.id, live_package.id ], @workflow.steps.not_deleted.reorder(:position).pluck(:id)
    assert_equal [ "Compile", "make" ], [ @build.reload.name, @build.instructions ]
    assert_equal "Ship {{step:#{@build.id}}}", live_package.instructions
    assert_equal [ @build.id ], live_package.depends_on_step_ids
    assert @test.reload.deleted?, "a step the draft removed is retired on the original"
    assert_equal [ [ @lint.id, "lint --strict" ], [ nil, "format" ] ],
                 @build.sub_steps.active.order(:position).map { |s| [ (s.id if s.id == @lint.id), s.name ] }
    assert_equal "faster", @workflow.description
    assert_equal [ "saved", draft.id ], [ version.event.to_s, version.metadata["applied_from_draft_id"] ]
    assert draft.reload.archived?, "an applied draft is closed"
    assert_nil @workflow.open_draft
  end

  test "a draft made before a live change asks before replacing it" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    save_draft(draft, Versions::Snapshot.dump(draft)["steps"], "description" => "from the draft")
    Versions.save!(@workflow, actor: @actor) { @workflow.update!(name: "Release (hotfix)") }

    error = assert_raises(WorkflowDrafts::LiveChanged) { WorkflowDrafts.apply!(draft, actor: @actor) }
    assert_equal [ draft.draft_base_version, @workflow.reload.current_version_number ],
                 [ error.base_version, error.live_version ]
    assert_equal "Release (hotfix)", @workflow.name
    assert_not draft.reload.archived?

    WorkflowDrafts.apply!(draft, actor: @actor, overwrite: true)
    @workflow.reload
    assert_equal [ "Release", "from the draft" ], [ @workflow.name, @workflow.description ]
  end

  test "a step deleted on the original after the draft was made comes back as a new step" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    @test.destroy!

    WorkflowDrafts.apply!(draft, actor: @actor, overwrite: true)

    names = @workflow.steps.not_deleted.reorder(:position)
    assert_equal %w[Build Test], names.pluck(:name)
    assert_not_equal @test.id, names.last.id
    assert_equal [ @build.id ], names.last.depends_on_step_ids
  end

  test "the builder's unsaved Save becomes a new draft and leaves the original alone" do
    aggregate = {
      "name" => "Release", "description" => "draft edits",
      "steps" => [
        { "id" => @build.id, "name" => "Build", "sub_steps" => [ { "id" => @lint.id, "name" => "lint" } ] },
        { "key" => "new-1", "name" => "Smoke", "depends_on_step_ids" => [ @build.id ] },
        { "id" => @test.id, "name" => "Test", "depends_on_step_ids" => [ "new-1" ],
          "instructions" => "after {{step:#{@build.id}}}" }
      ]
    }

    draft = WorkflowDrafts.open!(@workflow, actor: @actor, aggregate: aggregate)

    build = draft_step(draft, "Build")
    smoke = draft_step(draft, "Smoke")
    test = draft_step(draft, "Test")
    assert_equal %w[Build Smoke Test], draft.steps.not_deleted.reorder(:position).pluck(:name)
    assert_equal [ smoke.id ], test.depends_on_step_ids
    assert_equal "after {{step:#{build.id}}}", test.instructions
    assert_equal [ @lint.id ], build.sub_steps.active.map(&:origin_sub_step_id)
    assert_equal [ "draft edits", 2 ], [ draft.description, draft.current_version_number ]
    assert_equal [ "A test workflow", %w[Build Test] ],
                 [ @workflow.reload.description, @workflow.steps.not_deleted.reorder(:position).pluck(:name) ]
    error = assert_raises(WorkflowDrafts::Error) { WorkflowDrafts.open!(@workflow, actor: @actor, aggregate: aggregate) }
    assert_match(/already has a draft/, error.message)
  end

  test "changes show the draft in the original's step ids, with added steps matching nothing" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    build = draft_step(draft, "Build")
    save_draft(draft, [
      { "id" => build.id, "name" => "Build", "instructions" => "make all",
        "sub_steps" => [ { "id" => build.sub_steps.first.id, "name" => "lint" } ] },
      { "key" => "new-1", "name" => "Smoke", "depends_on_step_ids" => [ build.id ] }
    ])

    changes = WorkflowDrafts.changes(draft)

    smoke = draft_step(draft, "Smoke")
    assert_equal [ @build.id, "new-#{smoke.id}" ], changes[:draft]["steps"].pluck("id")
    assert_equal [ @build.id ], changes[:draft]["steps"].last["depends_on_step_ids"]
    assert_equal [ @lint.id ], changes[:draft]["steps"].first["sub_steps"].pluck("id")
    assert_includes changes[:references]["Tool"].keys, @tool.id.to_s
    summary = WorkflowDrafts::ChangeSummary.call(changes[:live], changes[:draft])
    assert_equal [
      { "change" => "step_removed", "step" => "Test", "step_id" => @test.id },
      { "change" => "step_changed", "step" => "Build", "step_id" => @build.id,
        "fields" => { "instructions" => { "before" => "Do the thing", "after" => "make all" } } },
      { "change" => "step_added", "step" => "Smoke", "position" => 2 }
    ], summary
  end

  test "a discarded draft leaves the original as it was and makes room for a new one" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    save_draft(draft, [], "description" => "gone")

    WorkflowDrafts.discard!(draft, actor: @actor)

    assert draft.reload.archived?
    assert_equal [ "A test workflow", 2 ], [ @workflow.reload.description, @workflow.steps.not_deleted.count ]
    error = assert_raises(WorkflowDrafts::Error) { WorkflowDrafts.apply!(draft, actor: @actor) }
    assert_match(/already applied or discarded/, error.message)
    assert_not_equal draft, WorkflowDrafts.open!(@workflow, actor: @actor)
  end

  test "archiving the live workflow closes its draft" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)

    Versions.archive!(@workflow, actor: @actor)

    assert draft.reload.archived?
    assert_raises(WorkflowDrafts::Error) { WorkflowDrafts.open!(@workflow.reload, actor: @actor) }
  end

  test "a draft cannot be bound, published, or drafted again" do
    draft = WorkflowDrafts.open!(@workflow, actor: @actor)
    column = create(:board_column, board: create(:board, project: @project))

    binding = ColumnWorkflowBinding.new(board_column: column, workflow: draft)
    trigger = build(:trigger_binding, workflow: draft, project: @project)
    assert_not binding.valid?
    assert_includes binding.errors[:workflow], "is a draft: columns start the live workflow"
    assert_not trigger.valid?
    assert_includes trigger.errors[:workflow], "is a draft: triggers start the live workflow"
    assert_raises(ActiveRecord::RecordInvalid) { draft.publish!(@user) }
    assert_raises(WorkflowDrafts::Error) { WorkflowDrafts.open!(draft, actor: @actor) }
  end
end
