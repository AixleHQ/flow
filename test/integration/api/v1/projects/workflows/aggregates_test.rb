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

  test "dependencies are written on the saved steps without reloading each one by id" do
    assert_no_queries_match(/FROM "steps" WHERE "steps"\."id" = .* LIMIT /) do
      save([
        { id: @build.id, name: "Build" },
        { key: "new-1", name: "Package", depends_on_step_ids: [ @build.id ] },
        { id: @test.id, name: "Test", depends_on_step_ids: [ "new-1" ] }
      ])
    end

    assert_response :success
    package = @workflow.steps.not_deleted.find_by!(name: "Package")
    assert_equal [ @build.id ], package.depends_on_step_ids
    assert_equal [ package.id ], @test.reload.depends_on_step_ids
  end

  test "a step's reasoning effort is saved and read back" do
    save([ { id: @build.id, name: "Build", required_agent_runtime: "kiro_cli", preferred_model: "claude-opus-5.5",
             reasoning_effort: "high" },
           { id: @test.id, name: "Test", depends_on_step_ids: [ @build.id ] } ])

    assert_response :success
    assert_equal "high", @build.reload.reasoning_effort
    assert_equal "high", response.parsed_body["steps"].find { |s| s["id"] == @build.id }["reasoningEffort"]
  end

  test "a reasoning effort the step's runtime does not take is refused and nothing is written" do
    # The refusal comes from the first step's save, before the sub-steps the sync
    # preloads are read, which Bullet would report as an unused eager load.
    Bullet.enable = false
    save([ { id: @build.id, name: "Build", required_agent_runtime: "gemini_cli", preferred_model: "gemini-3-pro",
             reasoning_effort: "medium" },
           { id: @test.id, name: "Test", depends_on_step_ids: [ @build.id ] } ])

    assert_response :unprocessable_entity
    assert_match(/Reasoning effort medium is not available for gemini_cli/, response.parsed_body["error"])
    assert_nil @build.reload.required_agent_runtime
  ensure
    Bullet.enable = true
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

  test "the builder's camelCase payload is understood, draft keys and config included" do
    put api_v1_project_workflow_aggregate_path(@project, @workflow),
        params: {
          baseVersion: @workflow.reload.current_version_number,
          aggregate: {
            name: "Release", description: "",
            config: { base_tool_ids: [], inherit_all_project_resources: true },
            steps: [
              { id: @build.id, key: @build.id.to_s, name: "Build", allowNonInteractive: true,
                outputAssetSpecs: [ { name: "report", assetType: "file", required: true, namePattern: "*.md" } ],
                dependsOnStepIds: [], subSteps: [ { id: @lint.id, name: "lint", required: false } ] },
              { id: nil, key: "new-1", name: "Ship", dependsOnStepIds: [ @build.id.to_s ], subSteps: [] }
            ]
          }
        }, as: :json

    assert_response :success
    assert @build.reload.allow_non_interactive
    assert_equal [ { "name" => "report", "asset_type" => "file", "required" => true, "name_pattern" => "*.md" } ],
                 @build.output_asset_specs
    assert_not @lint.reload.required
    assert_equal [ @build.id ], @workflow.steps.not_deleted.find_by!(name: "Ship").depends_on_step_ids
    assert @workflow.reload.inherit_all_project_resources
    assert @test.reload.deleted?
  end

  test "a save attaches the project's AWS roles to a step and to the base list" do
    role = create(:aws_oidc_role, integration: create(:integration, :aws_oidc, company: @company, project: @project))

    save([ { id: @build.id, name: "Build", awsOidcRoleIds: [ role.id ] }, { id: @test.id, name: "Test" } ],
         config: { baseAwsOidcRoleIds: [ role.id ] })

    assert_response :success
    assert_equal [ role.id ], @build.reload.aws_oidc_role_ids
    assert_equal [ role.id ], @workflow.reload.base_aws_oidc_role_ids
    assert_equal [ role.id ], response.parsed_body["steps"].find { |s| s["id"] == @build.id }["awsOidcRoleIds"]
    assert_equal [ role.id ], response.parsed_body.dig("workflow", "baseAwsOidcRoleIds")
  end

  test "a save naming another project's AWS role is refused" do
    # The refusal comes from the first step's save, before the sub-steps the sync
    # preloads are read, which Bullet would report as an unused eager load.
    Bullet.enable = false
    save([ { id: @build.id, name: "Build", awsOidcRoleIds: [ create(:aws_oidc_role).id ] }, { id: @test.id, name: "Test" } ])

    assert_response :unprocessable_entity
    assert_empty @build.reload.aws_oidc_role_ids
  ensure
    Bullet.enable = true
  end

  test "a save attaches the project's integrations to a step and to the base list" do
    coder = create(:integration, :coder, :active, company: @company, project: @project)
    slack = Integration.create!(provider: :teams, company: @company, connected_by: @owner, name: "Contoso",
                                status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })

    save([ { id: @build.id, name: "Build", integrationIds: [ coder.id ] }, { id: @test.id, name: "Test" } ],
         config: { baseIntegrationIds: [ slack.id ] })

    assert_response :success
    assert_equal [ coder.id ], @build.reload.integration_ids
    assert_equal [ slack.id ], @workflow.reload.base_integration_ids
    assert_equal [ coder.id ], response.parsed_body["steps"].find { |s| s["id"] == @build.id }["integrationIds"]
    assert_equal [ slack.id ], response.parsed_body.dig("workflow", "baseIntegrationIds")
  end

  test "a save naming an integration of another project, another company or an unknown id is refused" do
    Bullet.enable = false
    other_project = create(:project, company: @company, owner: @user)
    foreign = [ create(:integration, :coder, :active, company: @company, project: other_project),
                create(:integration, :coder, :active, company: create(:company)), 0 ]

    foreign.each do |integration|
      id = integration.respond_to?(:id) ? integration.id : integration
      save([ { id: @build.id, name: "Build", integrationIds: [ id ] }, { id: @test.id, name: "Test" } ])
      assert_response :unprocessable_entity
    end
    assert_empty @build.reload.integration_ids
  ensure
    Bullet.enable = true
  end

  test "a save naming a GitHub or an AWS integration is refused: only Coder, Slack, Teams and Azure DevOps attach" do
    Bullet.enable = false
    github = create(:integration, :github_pat, :active, company: @company, project: @project)

    save([ { id: @build.id, name: "Build", integrationIds: [ github.id ] }, { id: @test.id, name: "Test" } ])

    assert_response :unprocessable_entity
    assert_empty @build.reload.integration_ids
  ensure
    Bullet.enable = true
  end

  test "a reference to a step created in the same save is stored with that step's id" do
    save([
      { id: @build.id, name: "Build", output_asset_specs: [ { name: "dist.md", required: true } ] },
      { key: "new-1", name: "Package", depends_on_step_ids: [ @build.id ] },
      { id: @test.id, name: "Test", depends_on_step_ids: [ "new-1" ],
        instructions: "Read {{output:#{@build.id}:dist.md}} after {{step:new-1}}." }
    ])

    assert_response :success
    package = @workflow.steps.not_deleted.find_by!(name: "Package")
    assert_equal "Read {{output:#{@build.id}:dist.md}} after {{step:#{package.id}}}.", @test.reload.instructions
    assert_empty response.parsed_body["issues"]
  end

  test "the save response and the check report what a run would trip on, without blocking the save" do
    steps = [
      { id: @build.id, name: "Build", instructions: "Read {{output:#{@test.id}:report.md}}." },
      { id: @test.id, name: "Test", depends_on_step_ids: [ @build.id ], output_asset_specs: [ { name: "report.md" } ] }
    ]

    before = @build.instructions

    post check_api_v1_project_workflow_aggregate_path(@project, @workflow),
         params: { aggregate: { name: "Release", steps: steps } }, as: :json

    assert_response :success
    issue = response.parsed_body["issues"].sole
    assert_equal [ "output_not_upstream", @build.id.to_s, "error" ], issue.values_at("code", "stepKey", "severity")
    assert_equal before, @build.reload.instructions, "a check writes nothing"

    save(steps)

    assert_response :success
    assert_equal [ "output_not_upstream" ], response.parsed_body["issues"].pluck("code")
    assert_equal "Read {{output:#{@test.id}:report.md}}.", @build.reload.instructions
  end
end
