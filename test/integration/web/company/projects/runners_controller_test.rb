# frozen_string_literal: true

require "test_helper"

# A project's runners page (docs/design/agent-runtimes/DESIGN.md §3.2): project
# readers see the project's runners and the company's; a company admin or the
# project owner manages the project's own, and nobody manages a company runner
# from here.
class Web::Company::Projects::RunnersControllerTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  MANAGE_ROLES = { owner: :allowed_write, admin: :allowed_write, collaborator: :denied, viewer: :denied,
                   stranger: :not_found, foreign_admin: :not_found }.freeze

  setup do
    setup_project_authz_personas
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    @own = create(:runner, company: @company, project: @project, created_by: @owner, name: "Project box")
    @company_runner = create(:runner, company: @company, created_by: @admin, name: "Company box")
  end

  teardown { teardown_authz }

  test "every route answers 404 for a company without the flag" do
    FeatureFlagOverride.where(company: @company).delete_all
    sign_in_as(@owner)

    get company_project_runners_path(@project)
    assert_response :not_found
    get company_project_runner_path(@project, @own)
    assert_response :not_found
    post company_project_runners_path(@project), params: { runner: { name: "X", runner_type: "manual", max_concurrency: 1 } }, as: :json
    assert_response :not_found
    patch company_project_runner_path(@project, @own), params: { runner: { name: "Renamed" } }, as: :json
    assert_response :not_found
    %i[disable enable revoke registration_token].each do |action|
      post public_send(:"#{action}_company_project_runner_path", @project, @own)
      assert_response :not_found
    end
    delete company_project_runner_path(@project, @own)
    assert_response :not_found
    assert_empty RunnerCredential.all
    assert_equal "pending", @own.reload.status
  end

  test "project readers see the project's runners and the company's" do
    other = create(:runner, :project_runner, company: @company, created_by: @admin)

    assert_project_read { get company_project_runners_path(@project) }
    assert_project_read { get company_project_runner_path(@project, @company_runner) }

    sign_in_as(@collaborator)
    get company_project_runners_path(@project)
    assert_inertia_page "Projects/Runners/RunnersPage"
    assert_inertia_props do |props|
      props[:runners].pluck(:id).sort == [ @own.id, @company_runner.id ].sort &&
        props[:runners].pluck(:id).exclude?(other.id) && props[:canManage] == false
    end

    get company_project_runner_path(@project, other)
    assert_response :not_found
  end

  test "a company admin or the project owner creates a project runner, scoped to the project" do
    assert_role_matrix(MANAGE_ROLES, transport: :web) do |role|
      post company_project_runners_path(@project),
           params: { runner: { name: "Box #{role}", runner_type: "manual", max_concurrency: 1 } }, as: :json
    end

    created = Runner.where("name LIKE 'Box %'").order(:name)
    assert_equal [ "Box admin", "Box owner" ], created.pluck(:name)
    assert(created.all? { |runner| runner.project_id == @project.id && runner.company_id == @company.id })
    assert_equal @owner, created.find_by!(name: "Box owner").created_by
    assert_equal({ "provisionable" => false, "rebuildable" => false }, created.first.capabilities)
  end

  test "a company admin or the project owner updates and cycles the project's own runner" do
    assert_role_matrix(MANAGE_ROLES, transport: :web) do |role|
      patch company_project_runner_path(@project, @own), params: { runner: { name: "Renamed by #{role}" } }, as: :json
    end
    assert_equal "Renamed by admin", @own.reload.name

    assert_role_matrix(MANAGE_ROLES, transport: :web) do
      @own.update_columns(status: "pending", disabled_at: nil)
      post disable_company_project_runner_path(@project, @own)
    end

    sign_in_as(@owner)
    post enable_company_project_runner_path(@project, @own)
    assert_equal "pending", @own.reload.status
    post revoke_company_project_runner_path(@project, @own)
    assert_equal "revoked", @own.reload.status
    delete company_project_runner_path(@project, @own)
    assert @own.reload.deleted?
  end

  # A write finds the runner among the project's own, so a company runner is
  # not found by one, whoever asks.
  test "nobody manages a company runner from a project page" do
    %i[admin owner].each do |role|
      sign_in_as(user_for(role))

      patch company_project_runner_path(@project, @company_runner), params: { runner: { name: "Hijacked" } }, as: :json
      assert_response :not_found
      %i[disable enable revoke registration_token].each do |action|
        post public_send(:"#{action}_company_project_runner_path", @project, @company_runner)
        assert_response :not_found
      end
      delete company_project_runner_path(@project, @company_runner)
      assert_response :not_found
    end
    assert_empty RunnerCredential.all

    @company_runner.reload
    assert_equal "Company box", @company_runner.name
    assert_equal "pending", @company_runner.status
    assert_not @company_runner.deleted?

    get company_project_runner_path(@project, @company_runner)
    assert_inertia_props { |props| props[:canManage] == false }
  end

  test "a disabled company runner cannot be enabled from a project page" do
    @company_runner.disable!
    sign_in_as(@owner)

    post enable_company_project_runner_path(@project, @company_runner)

    assert_response :not_found
    assert_equal "disabled", @company_runner.reload.status
  end

  test "the show page's can_manage is the policy's answer and whether the runner is the project's own" do
    sign_in_as(@owner)
    get company_project_runner_path(@project, @own)
    assert_inertia_props { |props| props[:canManage] == true }

    sign_in_as(@collaborator)
    get company_project_runner_path(@project, @own)
    assert_inertia_props { |props| props[:canManage] == false }
  end

  test "another project's runner is not found by a write from this page" do
    other = create(:runner, :project_runner, company: @company, created_by: @admin)
    sign_in_as(@admin)

    patch company_project_runner_path(@project, other), params: { runner: { name: "Hijacked" } }, as: :json
    assert_response :not_found
    delete company_project_runner_path(@project, other)
    assert_response :not_found
    assert_not other.reload.deleted?
  end

  test "coder and kubernetes runners are refused as not available yet" do
    sign_in_as(@owner)

    assert_no_difference -> { Runner.count } do
      post company_project_runners_path(@project),
           params: { runner: { name: "K8s", runner_type: "kubernetes", max_concurrency: 1, config: { namespace: "aixle" } } }, as: :json
    end
    assert_includes Array(session["inertia_errors"][:runner_type]), "is not available yet"
  end

  test "a company admin or the project owner gets a registration token for the project's own runner" do
    body = nil
    assert_role_matrix(MANAGE_ROLES, transport: :web, allowed_status: :created) do |role|
      post registration_token_company_project_runner_path(@project, @own), as: :json
      body = response.parsed_body if role == :admin
    end

    assert_equal 2, RunnerCredential.where(kind: :registration, runner: @own).count
    assert_match(/\Aarreg_/, body["token"])
    assert_equal "#{Settings.protocol}://#{Settings.domain}/runner/v1/releases/#{body['version']}/linux-arm64", body["binaries"].last["url"]
  end

  test "a revoked project runner is refused with runner_revoked" do
    @own.revoke!
    sign_in_as(@owner)

    post registration_token_company_project_runner_path(@project, @own), as: :json

    assert_response :conflict
    assert_equal "runner_revoked", response.parsed_body["code"]
    assert_empty RunnerCredential.all
  end
end
