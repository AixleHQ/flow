# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::Workflows::DraftsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @workflow = create(:workflow, scope: @project, name: "Release")
    @build = create(:step, workflow: @workflow, name: "Build", position: 1)
    sign_in_as(@owner)
  end

  def open_draft(**body)
    post api_v1_project_workflow_draft_path(@project, @workflow), params: body, as: :json
    @workflow.reload.open_draft
  end

  test "the builder's unsaved Save opens a draft holding it, and the live workflow keeps running as it was" do
    draft = open_draft(aggregate: { name: "Release", steps: [ { id: @build.id, name: "Build", instructions: "make -j8" } ] })

    assert_response :created
    assert_equal [ draft.id, draft_company_project_workflow_path(@project, @workflow) ],
                 response.parsed_body.values_at("draftId", "url")
    assert_equal "make -j8", draft.steps.not_deleted.sole.instructions
    assert_equal "Do the thing", @build.reload.instructions

    post api_v1_project_workflow_draft_path(@project, @workflow), params: { aggregate: { name: "Release", steps: [] } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/already has a draft/, response.parsed_body["errors"].first)
  end

  test "changes are the live snapshot and the draft in live step ids, with the names of what they reference" do
    draft = open_draft
    put api_v1_project_workflow_aggregate_path(@project, draft),
        params: { base_version: draft.current_version_number,
                  aggregate: { name: "Release", steps: [ { id: draft.steps.sole.id, name: "Compile" } ] } }, as: :json

    get changes_api_v1_project_workflow_draft_path(@project, @workflow)

    assert_response :success
    body = response.parsed_body
    assert_equal [ [ @build.id, "Build" ] ], body["live"]["steps"].map { |s| s.values_at("id", "name") }
    assert_equal [ [ @build.id, "Compile" ] ], body["draft"]["steps"].map { |s| s.values_at("id", "name") }
    assert_equal [ 1, 1, 2 ], body.values_at("liveVersionNumber", "baseVersionNumber", "draftVersionNumber")
  end

  test "apply asks before replacing a live change, then applies over it when told to" do
    draft = open_draft
    put api_v1_project_workflow_aggregate_path(@project, draft),
        params: { base_version: draft.current_version_number,
                  aggregate: { name: "Release", steps: [ { id: draft.steps.sole.id, name: "Compile" } ] } }, as: :json
    put api_v1_project_workflow_aggregate_path(@project, @workflow),
        params: { base_version: @workflow.reload.current_version_number,
                  aggregate: { name: "Release", steps: [ { id: @build.id, name: "Build (hotfix)" } ] } }, as: :json

    post apply_api_v1_project_workflow_draft_path(@project, @workflow), as: :json

    assert_response :conflict
    assert_equal [ 1, 2 ], response.parsed_body.values_at("baseVersionNumber", "liveVersionNumber")
    assert_equal "Build (hotfix)", @build.reload.name

    post apply_api_v1_project_workflow_draft_path(@project, @workflow), params: { overwrite: true }, as: :json

    assert_response :success
    assert_equal [ 3, true, builder_company_project_workflow_path(@project, @workflow) ],
                 response.parsed_body.values_at("currentVersionNumber", "versionCreated", "url")
    assert_equal "Compile", @build.reload.name
    assert_nil @workflow.reload.open_draft
  end

  test "the history marks the version a draft was applied as" do
    draft = open_draft
    put api_v1_project_workflow_aggregate_path(@project, draft),
        params: { base_version: draft.current_version_number,
                  aggregate: { name: "Release", steps: [ { id: draft.steps.sole.id, name: "Compile" } ] } }, as: :json
    post apply_api_v1_project_workflow_draft_path(@project, @workflow), as: :json
    applied = response.parsed_body["currentVersionNumber"]

    get api_v1_project_entity_versions_path(@project, versionable_type: "Workflow", versionable_id: @workflow.id)

    marks = response.parsed_body["versions"].to_h { |version| [ version["number"], version["appliedFromDraft"] ] }
    assert marks.delete(applied)
    assert marks.any?
    assert_not marks.values.any?
  end

  test "discard closes the draft and leaves the live workflow untouched" do
    draft = open_draft

    delete api_v1_project_workflow_draft_path(@project, @workflow), as: :json

    assert_response :success
    assert draft.reload.archived?
    get changes_api_v1_project_workflow_draft_path(@project, @workflow)
    assert_response :not_found
  end

  test "a trigger cannot be put on a draft" do
    draft = open_draft

    post api_v1_project_workflow_triggers_path(@project, draft),
         params: { trigger: { kind: "webhook", name: "hook" } }, as: :json

    assert_response :unprocessable_entity
    assert_match(/is a draft: triggers start the live workflow/, response.body)
    assert_empty draft.trigger_bindings
  end
end
