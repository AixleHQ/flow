# frozen_string_literal: true

require "test_helper"

# Success-path coverage for WorkspacePreparator#resolve_instructions — the
# boundary-free public method that rewrites {{placeholder}} tokens in a step's
# instructions to concrete /workspace/input paths, driven by the run's assets.
#
# (prepare! and the private mount_/generate_ helpers talk to the container via
# the undefined `DockerClient` constant and are covered in the manifest's
# "uncertain" list rather than exercised here.)
class WorkspacePreparatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @company)
    @workflow_run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
    # A distinct earlier step_run that "produced" prior run assets.
    @previous_step_run = create(:step_run, workflow_run: @workflow_run,
      step: create(:step, workflow: @workflow))
  end

  def build_step_run(instructions)
    step = create(:step, workflow: @workflow, instructions: instructions)
    create(:step_run, workflow_run: @workflow_run, step: step)
  end

  test "returns an empty string unchanged when instructions are blank" do
    step_run = build_step_run("")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "", result
  end

  test "returns instructions verbatim when there are no placeholders" do
    step_run = build_step_run("Summarize the discussion and write a report.")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "Summarize the discussion and write a report.", result
  end

  test "resolves a placeholder to a workflow run asset produced by a previous step" do
    create(:workflow_run_asset, workflow_run: @workflow_run,
      produced_by_step_run: @previous_step_run, name: "report.md")
    step_run = build_step_run("Continue from {{report}} and expand it.")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "Continue from /workspace/input/report.md and expand it.", result
  end

  test "resolves a placeholder to a project asset selected at workflow start" do
    asset = create(:asset, scope: @project, created_by: @user, name: "spec.pdf")
    @workflow_run.update!(input_asset_ids: [ asset.id ])
    step_run = build_step_run("Follow the requirements in {{spec}}.")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "Follow the requirements in /workspace/input/spec.pdf.", result
  end

  test "leaves an unknown placeholder untouched" do
    step_run = build_step_run("Use {{missing}} if you can find it.")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "Use {{missing}} if you can find it.", result
  end

  test "does not resolve an asset produced by the step being prepared" do
    step_run = build_step_run("Overwrite {{draft}} in place.")
    # Asset produced by the current step_run must be excluded from the map.
    create(:workflow_run_asset, workflow_run: @workflow_run,
      produced_by_step_run: step_run, name: "draft.md")

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal "Overwrite {{draft}} in place.", result
  end

  test "resolves multiple placeholders mixing run and project assets in one pass" do
    project_asset = create(:asset, scope: @project, created_by: @user, name: "style_guide.md")
    @workflow_run.update!(input_asset_ids: [ project_asset.id ])
    create(:workflow_run_asset, workflow_run: @workflow_run,
      produced_by_step_run: @previous_step_run, name: "research_notes.md")
    step_run = build_step_run(
      "Apply {{style_guide}} to {{research_notes}}; ignore {{nonexistent}}."
    )

    result = WorkspacePreparator.new(step_run).resolve_instructions

    assert_equal(
      "Apply /workspace/input/style_guide.md to " \
      "/workspace/input/research_notes.md; ignore {{nonexistent}}.",
      result
    )
  end
end
