# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::Workflows::AggregatesTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @workflow = create(:workflow, scope: @project, name: "Release")
    @build = create(:step, workflow: @workflow, name: "Build", position: 1)
    @test = create(:step, workflow: @workflow, name: "Test", position: 2, depends_on_step_ids: [ @build.id ])
    @lint = create(:sub_step, step: @build, name: "lint", position: 1)
    sign_in_as(@owner)
  end

  def save(steps, base_version: @workflow.reload.current_version_number, **workflow)
    put api_v1_project_workflow_aggregate_path(@project, @workflow),
        params: { base_version: base_version, aggregate: { name: "Release", **workflow, steps: steps } }, as: :json
  end

  test "one save rewrites the workflow and records exactly one version" do
    save([
      { id: @build.id, name: "Build", instructions: "make", sub_steps: [ { id: @lint.id, name: "lint" }, { name: "format" } ] },
      { key: "new-1", name: "Package", depends_on_step_ids: [ @build.id ] },
      { id: @test.id, name: "Test", depends_on_step_ids: [ "new-1" ] }
    ], description: "shipped")

    assert_response :success
    package = @workflow.steps.not_deleted.find_by!(name: "Package")
    assert_equal %w[Build Package Test], @workflow.steps.not_deleted.reorder(:position).pluck(:name)
    assert_equal [ package.id ], @test.reload.depends_on_step_ids
    assert_equal %w[lint format], @build.sub_steps.active.order(:position).pluck(:name)
    assert_equal "shipped", @workflow.reload.description
    assert_equal [ "created", "saved" ], @workflow.entity_versions.reorder(:number).map { |v| v.event.to_s }
    assert_equal 2, response.parsed_body["currentVersionNumber"]
  end

  test "steps left out are soft-deleted, not removed" do
    save([ { id: @build.id, name: "Build", sub_steps: [] } ])

    assert_response :success
    assert @test.reload.deleted?
    assert @lint.reload.deleted?
  end

  test "a save from a stale base version answers 409 and writes nothing" do
    Versions.save!(@workflow, actor: Versions::Actor.ui(@owner)) { @workflow.update!(description: "someone else") }

    save([ { id: @build.id, name: "Renamed" } ], base_version: 1)

    assert_response :conflict
    assert_equal "Build", @build.reload.name
    assert_not @test.reload.deleted?
  end

  test "a dependency on a step that is not in the payload is refused before anything is written" do
    save([ { id: @test.id, name: "Test", depends_on_step_ids: [ @build.id ] } ])

    assert_response :unprocessable_entity
    assert_match(/depends on a step that is not in the workflow/, response.parsed_body["errors"].first)
    assert_not @build.reload.deleted?
  end

  test "a save that changes nothing records no version" do
    Versions.save!(@workflow, actor: Versions::Actor.ui(@owner)) { @workflow.update!(description: "d") }

    save([
      { id: @build.id, name: "Build", instructions: @build.instructions,
        sub_steps: [ { id: @lint.id, name: "lint", instructions: @lint.instructions, required: true } ] },
      { id: @test.id, name: "Test", instructions: @test.instructions, depends_on_step_ids: [ @build.id ] }
    ], description: "d")

    assert_response :success
    assert_equal false, response.parsed_body["versionCreated"] # rubocop:disable Minitest/RefuteFalse
  end

  test "an invalid step rolls the whole save back" do
    save([ { id: @build.id, name: "" }, { key: "x", name: "New" } ])

    assert_response :unprocessable_entity
    assert_equal "Build", @build.reload.name
    assert_nil @workflow.steps.find_by(name: "New")
  end
end
