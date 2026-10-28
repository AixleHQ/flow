# frozen_string_literal: true

require "test_helper"

# Company runners, a company settings tab (docs/design/agent-runtimes/DESIGN.md
# §3.2): every member reads, only a company admin writes, and the whole surface
# is a 404 for a company without the external_runners flag.
class Web::Company::RunnersControllerTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  READ_ROLES = { admin: :allowed_read, owner: :allowed_read, collaborator: :allowed_read, viewer: :allowed_read,
                 stranger: :allowed_read, foreign_admin: :not_found }.freeze
  WRITE_ROLES = { admin: :allowed_write, owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied,
                  foreign_admin: :not_found }.freeze

  setup do
    setup_company_authz_personas
    enable_runners(@company)
    @runner = create(:runner, company: @company, created_by: @admin, name: "Build box")
  end

  teardown { teardown_authz }

  def enable_runners(company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: company, enabled: true, reason: "test")
  end

  def runner_params(**overrides)
    { runner: { name: "Office Mac", runner_type: "manual", max_concurrency: 2, config: { reconnect_grace: 600 } }.merge(overrides) }
  end

  test "every route answers 404 for a company without the flag" do
    FeatureFlagOverride.where(company: @company).delete_all
    sign_in_as(@admin)

    get company_settings_runners_path
    assert_response :not_found
    get company_settings_runner_path(@runner)
    assert_response :not_found
    post company_settings_runners_path, params: runner_params, as: :json
    assert_response :not_found
    patch company_settings_runner_path(@runner), params: { runner: { name: "Renamed" } }, as: :json
    assert_response :not_found
    %i[disable enable revoke].each do |action|
      post public_send(:"#{action}_company_settings_runner_path", @runner)
      assert_response :not_found
    end
    delete company_settings_runner_path(@runner)
    assert_response :not_found
    assert_equal "Build box", @runner.reload.name
  end

  test "every member lists and views the company's runners" do
    assert_role_matrix(READ_ROLES, transport: :web) { get company_settings_runners_path }
    assert_role_matrix(READ_ROLES, transport: :web) { get company_settings_runner_path(@runner) }
  end

  test "index renders the runners, the available types and whether the user may manage" do
    project_runner = create(:runner, :project_runner, company: @company, created_by: @admin)
    sign_in_as(@admin)

    get company_settings_runners_path

    assert_inertia_page "Company/Settings/RunnersPage"
    assert_inertia_props do |props|
      props[:runners].pluck(:id) == [ @runner.id ] && !props[:runners].pluck(:id).include?(project_runner.id) &&
        props[:runners].first[:runnerType] == "manual" &&
        props[:runnerTypes].pluck(:runnerType) == %w[manual] &&
        props[:runnerTypes].first[:configSchema][:properties].key?(:reconnect_grace) &&
        props[:canManage] == true
    end

    sign_in_as(@owner)
    get company_settings_runner_path(@runner)
    assert_inertia_page "Company/Settings/RunnerPage"
    assert_inertia_props { |props| props[:runner][:name] == "Build box" && props[:canManage] == false }
  end

  test "only a company admin creates a company runner, and the request decides its scope and author" do
    assert_role_matrix(WRITE_ROLES, transport: :web) do |role|
      post company_settings_runners_path, params: runner_params(name: "Box #{role}"), as: :json
    end

    runner = @company.runners.find_by!(name: "Box admin")
    assert_nil runner.project_id
    assert_equal @admin, runner.created_by
    assert_equal({ "reconnect_grace" => 600 }, runner.config)
    assert_equal({ "provisionable" => false, "rebuildable" => false }, runner.capabilities)
    assert_equal 1, @company.runners.where("name LIKE 'Box %'").count
  end

  test "a scope or author in the params is ignored" do
    project = create(:project, company: @company, owner: @owner)
    sign_in_as(@admin)

    post company_settings_runners_path, params: runner_params(project_id: project.id, created_by_id: @owner.id), as: :json

    runner = @company.runners.find_by!(name: "Office Mac")
    assert_nil runner.project_id
    assert_equal @admin, runner.created_by
  end

  test "coder and kubernetes runners are refused as not available yet" do
    sign_in_as(@admin)

    assert_no_difference -> { Runner.count } do
      post company_settings_runners_path, params: runner_params(runner_runner_type: "kubernetes", config: { namespace: "aixle" }), as: :json
      assert_includes Array(session["inertia_errors"][:runner_type]), "is not available yet"
      post company_settings_runners_path, params: runner_params(runner_type: "coder"), as: :json
      assert_includes Array(session["inertia_errors"][:runner_type]), "is not available yet"
    end
  end

  test "a config the schema or the manual adapter refuses is not saved" do
    sign_in_as(@admin)

    assert_no_difference -> { Runner.count } do
      post company_settings_runners_path, params: runner_params(config: { execution_mode: "host" }), as: :json
      assert_includes Array(session["inertia_errors"][:config]), "execution_mode is not supported yet"

      post company_settings_runners_path, params: runner_params(config: { container: { docker_socket: true } }), as: :json
      assert_match(/docker_socket requires container.allow_privileged_mounts/, Array(session["inertia_errors"][:config]).to_sentence)
    end
  end

  test "only a company admin updates a company runner, and the capabilities are stored again" do
    @runner.update_columns(capabilities: {})

    assert_role_matrix(WRITE_ROLES, transport: :web) do |role|
      patch company_settings_runner_path(@runner), params: { runner: { name: "Renamed by #{role}", max_concurrency: 3 } }, as: :json
    end

    @runner.reload
    assert_equal "Renamed by admin", @runner.name
    assert_equal 3, @runner.max_concurrency
    assert_equal({ "provisionable" => false, "rebuildable" => false }, @runner.capabilities)
  end

  test "an admin disables, enables, revokes and deletes a company runner; the others cannot" do
    sign_in_as(@owner)
    post disable_company_settings_runner_path(@runner)
    assert_equal AuthorizationMatrix::DENIAL_ALERT, flash[:alert]
    assert_equal "pending", @runner.reload.status

    sign_in_as(@admin)
    post disable_company_settings_runner_path(@runner)
    assert_equal "disabled", @runner.reload.status
    post enable_company_settings_runner_path(@runner)
    assert_equal "pending", @runner.reload.status
    post revoke_company_settings_runner_path(@runner)
    assert_equal "revoked", @runner.reload.status

    post enable_company_settings_runner_path(@runner)
    assert_equal "A revoked runner cannot be enabled", flash[:alert]

    delete company_settings_runner_path(@runner)
    assert_redirected_to company_settings_runners_path
    assert @runner.reload.deleted?
    get company_settings_runner_path(@runner)
    assert_response :not_found
  end

  test "a project's runner is not reachable from company settings" do
    project_runner = create(:runner, :project_runner, company: @company, created_by: @admin)
    sign_in_as(@admin)

    get company_settings_runner_path(project_runner)
    assert_response :not_found
    delete company_settings_runner_path(project_runner)
    assert_response :not_found
    assert_not project_runner.reload.deleted?
  end
end
