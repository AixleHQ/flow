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

  def canonical_url = "#{Settings.protocol}://#{Settings.domain}"

  def runner_params(**overrides)
    { runner: { name: "Office Mac", runner_type: "manual", max_concurrency: 2, config: { auto_update: false } }.merge(overrides) }
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
    %i[disable enable revoke registration_token].each do |action|
      post public_send(:"#{action}_company_settings_runner_path", @runner)
      assert_response :not_found
    end
    delete company_settings_runner_path(@runner)
    assert_response :not_found
    assert_empty RunnerCredential.all
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
        props[:runnerTypes].first[:configSchema][:properties].key?(:auto_update) &&
        props[:canManage] == true
    end

    sign_in_as(@owner)
    get company_settings_runner_path(@runner)
    assert_inertia_page "Company/Settings/RunnerPage"
    assert_inertia_props { |props| props[:runner][:name] == "Build box" && props[:canManage] == false }
  end

  test "show lists the machines with their display state, and the runner's last seen" do
    idle = create(:runner_environment, runner: @runner, display_name: "mac", os: "darwin", arch: "arm64", runner_version: "0.2.0")
    silent = create(:runner_environment, runner: @runner, display_name: "gone-quiet", last_heartbeat_at: 5.minutes.ago)
    busy = create(:runner_environment, runner: @runner, display_name: "busy",
                                       current_session: create(:runner_session, environment: idle, runner_environment: nil))
    seen = Time.current.change(usec: 0)
    @runner.update!(last_seen_at: seen)
    sign_in_as(@owner)

    get company_settings_runner_path(@runner)

    assert_inertia_props do |props|
      machines = props[:machines].index_by { |machine| machine[:id] }
      props[:runner][:lastSeenAt].present? &&
        machines.keys == [ idle.id, silent.id, busy.id ] &&
        machines[idle.id].values_at(:displayName, :state, :os, :arch, :runnerVersion) == %w[mac idle darwin arm64 0.2.0] &&
        machines[silent.id][:state] == "offline" && machines[busy.id][:state] == "online" &&
        machines[idle.id][:key] == idle.key && machines[idle.id][:lastHeartbeatAt].present?
    end
  end

  test "a runner that is not manual has no machines" do
    runner = create(:runner, :kubernetes, company: @company, created_by: @admin)
    sign_in_as(@owner)

    get company_settings_runner_path(runner)

    assert_inertia_props { |props| props[:machines] == [] }
  end

  test "only a company admin creates a company runner, and the request decides its scope and author" do
    assert_role_matrix(WRITE_ROLES, transport: :web) do |role|
      post company_settings_runners_path, params: runner_params(name: "Box #{role}"), as: :json
    end

    runner = @company.runners.find_by!(name: "Box admin")
    assert_nil runner.project_id
    assert_equal @admin, runner.created_by
    assert_equal({ "auto_update" => false }, runner.config)
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
      post company_settings_runners_path, params: runner_params(runner_type: "kubernetes", config: { namespace: "aixle" }), as: :json
      assert_includes Array(session["inertia_errors"][:runner_type]), "is not available yet"
      post company_settings_runners_path, params: runner_params(runner_type: "coder"), as: :json
      assert_includes Array(session["inertia_errors"][:runner_type]), "is not available yet"
    end
  end

  test "a config the schema or the type's rules refuse is not saved, with the same message" do
    sign_in_as(@admin)

    assert_no_difference -> { Runner.count } do
      post company_settings_runners_path, params: runner_params(config: { execution_mode: "host" }), as: :json
      assert_includes Array(session["inertia_errors"][:config]), "execution_mode is not supported yet"

      post company_settings_runners_path, params: runner_params(config: { container: { docker_socket: true } }), as: :json
      assert_match(/docker_socket requires container.allow_privileged_mounts/, Array(session["inertia_errors"][:config]).to_sentence)

      post company_settings_runners_path, params: runner_params(config: {
        container: { extra_mounts: [ { source: "/srv/out", target: "/out", writable: true } ] }
      }), as: :json
      assert_equal [ "container.acknowledged_writable_mounts must list /out: it is a writable host mount" ],
                   Array(session["inertia_errors"][:config])
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
    patch company_settings_runner_path(project_runner), params: { runner: { name: "Hijacked" } }, as: :json
    assert_response :not_found
    %i[disable enable revoke registration_token].each do |action|
      post public_send(:"#{action}_company_settings_runner_path", project_runner)
      assert_response :not_found
    end
    delete company_settings_runner_path(project_runner)
    assert_response :not_found
    project_runner.reload
    assert_not project_runner.deleted?
    assert_equal "pending", project_runner.status
    assert_not_equal "Hijacked", project_runner.name
  end

  test "only a company admin gets a registration token, once, and only the digest is stored" do
    assert_role_matrix(WRITE_ROLES, transport: :web, allowed_status: :created) do
      post registration_token_company_settings_runner_path(@runner), as: :json
    end
    assert_equal 1, RunnerCredential.count, "only the admin was given a token"
    RunnerCredential.delete_all

    sign_in_as(@admin)
    post registration_token_company_settings_runner_path(@runner), as: :json
    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_match(/\Aarreg_/, body["token"])
    assert_equal canonical_url, body["gatewayUrl"]
    assert_equal Settings.runners.release.recommended_version, body["version"]
    assert_equal %w[linux-amd64 linux-arm64], body["binaries"].pluck("platform")
    assert_equal "#{canonical_url}/runner/v1/releases/#{body['version']}/linux-amd64", body["binaries"].first["url"]
    assert_equal Runners::Release.binary(body["version"], "linux-amd64").sha256, body["binaries"].first["sha256"]
    assert_in_delta 1.hour.from_now, Time.zone.parse(body["expiresAt"]), 5.seconds

    credential = RunnerCredential.find_by_token(body["token"], kind: :registration)
    assert_equal @runner, credential.runner
    assert_equal 1, RunnerCredential.count

    get company_settings_runner_path(@runner)
    assert_not_includes response.body, body["token"]
  end

  test "the gateway URL is the platform's own, whatever Host and X-Forwarded-Host say" do
    sign_in_as(@admin)

    post registration_token_company_settings_runner_path(@runner), as: :json,
                                                                   headers: { "Host" => "evil.example", "X-Forwarded-Host" => "evil.example" }

    assert_response :created
    body = response.parsed_body
    assert_equal canonical_url, body["gatewayUrl"]
    assert(body["binaries"].all? { |binary| binary["url"].start_with?("#{canonical_url}/runner/v1/releases/") })
    assert_not_includes response.body, "evil.example"
  end

  test "a revoked runner is refused with runner_revoked and no token" do
    @runner.revoke!
    sign_in_as(@admin)

    post registration_token_company_settings_runner_path(@runner), as: :json

    assert_response :conflict
    assert_equal "runner_revoked", response.parsed_body["code"]
    assert_empty RunnerCredential.all
  end

  test "a deleted runner is not found" do
    @runner.soft_delete!
    sign_in_as(@admin)

    post registration_token_company_settings_runner_path(@runner), as: :json

    assert_response :not_found
    assert_empty RunnerCredential.where(kind: :registration)
  end

  test "only a company admin returns a failed machine to service, which resets it" do
    machine = create(:runner_environment, runner: @runner, display_name: "build-01")
    Runners::Machines.fail!(machine, "build-01 failed to reset after session 7: boom")

    assert_role_matrix(WRITE_ROLES, transport: :web) do
      post return_to_service_company_settings_runner_machine_path(@runner, machine)
      Runners::Machines.fail!(machine.reload, "boom again") if machine.reload.state == "resetting"
    end

    RunnerOperation.delete_all
    sign_in_as(@admin)
    post return_to_service_company_settings_runner_machine_path(@runner, machine)
    assert_redirected_to company_settings_runner_path(@runner)
    assert_equal "build-01 is being reset. It takes sessions again once the reset succeeds.", flash[:notice]
    assert_equal "resetting", machine.reload.state
    assert_equal 1, RunnerOperation.where(runner_environment: machine, op: "env.reset", state: "pending").count
  end

  test "Return to service on a machine that is not failed sends nothing" do
    machine = create(:runner_environment, runner: @runner, display_name: "build-01")
    sign_in_as(@admin)

    post return_to_service_company_settings_runner_machine_path(@runner, machine)

    assert_equal "build-01 is not failed, so there is nothing to return to service.", flash[:alert]
    assert_equal "registered", machine.reload.state
    assert_empty RunnerOperation.all
  end

  test "Return to service of a machine whose runner is not manual sends nothing" do
    runner = create(:runner, :kubernetes, company: @company, created_by: @admin, name: "Cluster")
    machine = create(:runner_environment, runner: runner)
    Runners::Machines.fail!(machine, "boom")
    sign_in_as(@admin)

    post return_to_service_company_settings_runner_machine_path(runner, machine)

    assert_equal "Only a machine of a manual runner is returned to service.", flash[:alert]
    assert_equal "failed", machine.reload.state
    assert_empty RunnerOperation.all
  end

  test "a machine of another runner is not found by Return to service" do
    other = create(:runner_environment, runner: create(:runner, company: @company, created_by: @admin, name: "Other box"))
    Runners::Machines.fail!(other, "boom")
    sign_in_as(@admin)

    post return_to_service_company_settings_runner_machine_path(@runner, other)

    assert_response :not_found
    assert_equal "failed", other.reload.state
  end
end
