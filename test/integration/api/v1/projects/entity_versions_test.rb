# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::EntityVersionsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @actor = Versions::Actor.ui(@owner)
    sign_in_as(@owner)
  end

  test "index pages through the history newest first" do
    agent = create(:agent, scope: @project)
    25.times { |i| Versions.save!(agent, actor: @actor) { agent.update!(title: "Title #{i}") } }

    get api_v1_project_entity_versions_path(@project, versionable_type: "Agent", versionable_id: agent.id)
    first_page = response.parsed_body
    assert_equal (7..26).to_a.reverse, first_page["versions"].pluck("number")
    assert_equal 7, first_page["nextBefore"]
    assert_equal @owner.name, first_page["versions"].first.dig("author", "name")

    get api_v1_project_entity_versions_path(@project, versionable_type: "Agent", versionable_id: agent.id,
                                                      before: first_page["nextBefore"])
    last_page = response.parsed_body
    assert_equal (1..6).to_a.reverse, last_page["versions"].pluck("number")
    assert_nil last_page["nextBefore"]
    assert last_page["versions"].last["baseline"]
  end

  test "show returns both sides of the diff with snapshot keys verbatim" do
    skill = create(:skill, scope: @project, files: { "SKILL.md" => "one", "scripts/run_it.sh" => "echo" })
    Versions.save!(skill, actor: @actor) { skill.update!(files: { "SKILL.md" => "two" }) }

    get api_v1_project_entity_version_path(@project, skill.entity_versions.find_by(number: 2))

    body = response.parsed_body
    assert_equal({ "SKILL.md" => "two" }, body.dig("snapshot", "files"))
    assert_equal({ "SKILL.md" => "one", "scripts/run_it.sh" => "echo" }, body.dig("previousSnapshot", "files"))
    assert_equal "content_hash", body["snapshot"].keys.find { |k| k == "content_hash" }
    assert_equal 2, body["currentVersionNumber"]
  end

  test "show names the resources a workflow snapshot points at, flagging archived ones" do
    tool = create(:tool, scope: @project, display_name: "Deployer")
    workflow = create(:workflow, scope: @project)
    create(:step, workflow: workflow, tool_ids: [ tool.id ])
    Versions.save!(workflow, actor: @actor) { workflow.update!(description: "x") }
    tool.soft_delete!

    get api_v1_project_entity_version_path(@project, workflow.latest_version)

    assert_equal({ "name" => "Deployer", "archived" => true }, response.parsed_body.dig("references", "Tool", tool.id.to_s))
  end

  test "revert from a stale base version answers 409 and changes nothing" do
    agent = create(:agent, scope: @project, title: "One")
    Versions.save!(agent, actor: @actor) { agent.update!(title: "Two") }

    post revert_api_v1_project_entity_version_path(@project, agent.entity_versions.find_by(number: 1)),
         params: { base_version: 1 }, as: :json

    assert_response :conflict
    assert_equal 2, response.parsed_body["currentVersionNumber"]
    assert_equal "Two", agent.reload.title
  end

  test "revert applies the version and returns the new one" do
    agent = create(:agent, scope: @project, title: "One")
    Versions.save!(agent, actor: @actor) { agent.update!(title: "Two") }

    post revert_api_v1_project_entity_version_path(@project, agent.entity_versions.find_by(number: 1)),
         params: { base_version: 2 }, as: :json

    assert_response :success
    assert_equal [ 3, "reverted", 1 ], response.parsed_body.values_at("number", "event", "restoredFromNumber")
    assert_equal "One", agent.reload.title
  end

  test "a version of another project's entity is not found" do
    other = create(:project, company: @company, owner: @owner)
    agent = create(:agent, scope: other)
    Versions.save!(agent, actor: @actor) { agent.update!(title: "x") }

    get api_v1_project_entity_version_path(@project, agent.latest_version)
    assert_response :not_found

    get api_v1_project_entity_versions_path(@project, versionable_type: "Agent", versionable_id: agent.id)
    assert_response :not_found
  end

  test "restore brings an archived workflow back with the triggers asked for" do
    workflow = create(:workflow, scope: @project)
    trigger = create(:trigger_binding, workflow: workflow, project: @project, enabled: true)
    Versions.archive!(workflow, actor: @actor)

    post restore_api_v1_project_entity_versions_path(@project),
         params: { versionable_type: "Workflow", versionable_id: workflow.id, enable_trigger_ids: [ trigger.id ] }, as: :json

    assert_response :success
    assert_equal "restored", response.parsed_body["event"]
    assert_not workflow.reload.deleted?
    assert trigger.reload.enabled
  end

  test "restore refuses a name taken since, with the reason" do
    agent = create(:agent, scope: @project, name: "helper")
    Versions.archive!(agent, actor: @actor)
    create(:agent, scope: @project, name: "helper")

    post restore_api_v1_project_entity_versions_path(@project),
         params: { versionable_type: "Agent", versionable_id: agent.id }, as: :json

    assert_response :unprocessable_entity
    assert_match(/already exists/, response.body)
    assert agent.reload.archived?
  end
end
