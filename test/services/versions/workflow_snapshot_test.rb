# frozen_string_literal: true

require "test_helper"

class Versions::WorkflowSnapshotTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @actor = Versions::Actor.ui(@user)
    @workflow = create(:workflow, scope: @project, name: "Release")
    @build = create(:step, workflow: @workflow, name: "Build", position: 1, instructions: "build it")
    @test = create(:step, workflow: @workflow, name: "Test", position: 2, depends_on_step_ids: [ @build.id ])
    @check = create(:sub_step, step: @build, name: "lint", position: 1)
  end

  test "the snapshot holds live steps with their live sub-steps, in order" do
    create(:step, workflow: @workflow, name: "Gone", position: 3).soft_delete!

    snapshot = Versions::Snapshot.dump(@workflow)

    assert_equal %w[Build Test], snapshot["steps"].pluck("name")
    assert_equal [ @build.id ], snapshot["steps"].second["depends_on_step_ids"]
    assert_equal [ { "id" => @check.id, "name" => "lint", "instructions" => @check.instructions, "position" => 1, "required" => true } ],
                 snapshot["steps"].first["sub_steps"]
  end

  test "revert brings back deleted steps and sub-steps by id and retires steps added since" do
    Versions.save!(@workflow, actor: @actor) { @workflow.update!(description: "v1") }
    v1 = @workflow.latest_version

    Versions.save!(@workflow, actor: @actor) do
      @test.destroy
      @check.destroy
      @build.update!(instructions: "build it differently")
      create(:step, workflow: @workflow, name: "Deploy", position: 3)
      Positions.reorder!(@workflow.steps, [ @workflow.steps.not_deleted.find_by(name: "Deploy").id, @build.id ])
    end

    Versions.revert!(@workflow, to: v1, actor: @actor)

    live = @workflow.steps.not_deleted.reorder(:position).to_a
    assert_equal [ [ @build.id, "Build" ], [ @test.id, "Test" ] ], live.map { |s| [ s.id, s.name ] }
    assert_equal "build it", live.first.instructions
    assert_equal [ @build.id ], live.second.depends_on_step_ids
    assert_equal [ @check.id ], @build.reload.sub_steps.active.pluck(:id)
    assert @workflow.steps.find_by(name: "Deploy").deleted?
    assert_equal v1.snapshot["steps"], @workflow.reload.latest_version.snapshot["steps"]
  end

  test "revert restores a dependency chain whatever order the steps were saved in" do
    deploy = create(:step, workflow: @workflow, name: "Deploy", position: 3, depends_on_step_ids: [ @test.id ])
    Versions.save!(@workflow, actor: @actor) { @workflow.update!(description: "chain") }
    chain = @workflow.latest_version

    Versions.save!(@workflow, actor: @actor) do
      deploy.update!(depends_on_step_ids: [])
      @test.update!(depends_on_step_ids: [ deploy.id ])
    end

    Versions.revert!(@workflow, to: chain, actor: @actor)

    assert_equal [ @test.id ], deploy.reload.depends_on_step_ids
    assert_equal [ @build.id ], @test.reload.depends_on_step_ids
  end

  test "revert drops references to rows that no longer exist and keeps archived ones" do
    gone = create(:tool, scope: @project)
    archived = create(:tool, scope: @project)
    @build.update!(tool_ids: [ gone.id, archived.id ])
    Versions.save!(@workflow, actor: @actor) { @workflow.update!(description: "with tools") }
    with_tools = @workflow.latest_version

    Versions.save!(@workflow, actor: @actor) { @build.update!(tool_ids: []) }
    gone.tool_results.delete_all
    gone.delete
    archived.soft_delete!

    Versions.revert!(@workflow, to: with_tools, actor: @actor)

    assert_equal [ archived.id ], @build.reload.tool_ids
  end
end
