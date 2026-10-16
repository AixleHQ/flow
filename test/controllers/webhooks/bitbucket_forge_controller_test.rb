# frozen_string_literal: true

require "test_helper"

class Webhooks::BitbucketForgeControllerTest < ActionDispatch::IntegrationTest
  include ForgeTestHelper
  include ActiveJob::TestHelper

  setup do
    with_bitbucket_settings(app_mode: true)
    stub_forge_keys!
    @installation_id = forge_installation_ari
  end

  def invoke(path, body: {}, principal: nil, system_token: forge_system_token)
    token = forge_invocation_token(installation_id: @installation_id, principal: principal)
    post path, params: body.to_json, headers: forge_headers(token, system_token: system_token)
  end

  test "a heartbeat records the installation and stores the token it brings" do
    invoke(bitbucket_forge_heartbeat_path, system_token: forge_system_token(expires_at: 2.hours.from_now))

    assert_response :ok
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    assert installation.usable_token(min_remaining: 300)
    assert_in_delta Time.current, installation.last_invocation_at, 5
  end

  test "the install event keeps who installed the app" do
    invoke(bitbucket_forge_lifecycle_path, body: { id: "x", installerAccountId: "acct-7", app: { id: "a" } })

    assert_equal "acct-7", BitbucketInstallation.find_by!(forge_installation_id: @installation_id).installer_account_id
  end

  test "an invocation without a valid token is refused and records nothing" do
    post bitbucket_forge_heartbeat_path, params: "{}", headers: { "Authorization" => "Bearer junk", "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal 0, BitbucketInstallation.count
  end

  test "nothing is answered while app mode is not configured" do
    with_bitbucket_settings(app_mode: false)

    invoke(bitbucket_forge_heartbeat_path)

    assert_response :unauthorized
    assert_equal 0, BitbucketInstallation.count
  end

  test "a build-status event is a cue for the gates on that repository and commit" do
    event = { eventType: "avi:bitbucket:updated:build-status", repository: { uuid: "{AB12CD34-0000-4000-8000-000000000001}" },
              buildStatus: { key: "build", state: "SUCCESSFUL", commit: { hash: "abc123" } } }

    assert_enqueued_with(job: ResolveBitbucketBuildStatusJob,
                         args: [ { repository_uuid: "{ab12cd34-0000-4000-8000-000000000001}", commit: "abc123" } ]) do
      invoke(bitbucket_forge_events_path, body: { payload: event })
    end
    assert_response :ok
  end

  test "a renamed repository is re-read" do
    invoke(bitbucket_forge_events_path, body: { eventType: "avi:bitbucket:updated:repository", repository: { uuid: "{r-1}" } })

    assert_enqueued_jobs 1, only: RefreshBitbucketRepositoryJob
  end

  test "uninstalling takes the workspace's connections down" do
    invoke(bitbucket_forge_heartbeat_path)
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    company = create(:company)
    installation.update!(company: company)
    integration = create(:integration, :bitbucket_app, :active, company: company, bitbucket_installation: installation)

    invoke(bitbucket_forge_uninstall_path)

    assert_response :ok
    assert installation.reload.uninstalled?
    assert_equal "error", integration.reload.status
  end

  test "the settings page's Connect hands a workspace administrator the pairing link" do
    invoke(bitbucket_forge_heartbeat_path)
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    stub_workspace_permission(installation)

    invoke(bitbucket_forge_connect_path, principal: FORGE_ADMIN_ACCOUNT)

    assert_response :ok
    assert_equal true, response.parsed_body["ok"] # rubocop:disable Minitest/AssertTruthy
    assert_match %r{/integrations/bitbucket/connect#pairing=}, response.parsed_body["url"]
  end

  test "a refusal still answers 200, so the page can say why" do
    invoke(bitbucket_forge_heartbeat_path)
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    stub_workspace_permission(installation, permission: "member")

    invoke(bitbucket_forge_connect_path, principal: FORGE_ADMIN_ACCOUNT)

    assert_response :ok
    assert_equal [ false, "not_workspace_admin" ], response.parsed_body.values_at("ok", "error")
    assert_equal 0, BitbucketPairing.count
  end

  test "disconnecting unbinds the workspace and takes its connections down" do
    invoke(bitbucket_forge_heartbeat_path)
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    company = create(:company)
    installation.update!(company: company, bound_at: Time.current)
    integration = create(:integration, :bitbucket_app, :active, company: company, bitbucket_installation: installation)
    stub_workspace_permission(installation)

    invoke(bitbucket_forge_disconnect_path, principal: FORGE_ADMIN_ACCOUNT)

    assert_response :ok
    assert_equal false, response.parsed_body["bound"] # rubocop:disable Minitest/RefuteFalse
    assert_not installation.reload.bound?
    assert_equal "disconnected", integration.reload.settings["installation_state"]
  end

  test "status is shown to administrators only" do
    invoke(bitbucket_forge_heartbeat_path)
    installation = BitbucketInstallation.find_by!(forge_installation_id: @installation_id)
    stub_workspace_permission(installation, permission: nil)

    invoke(bitbucket_forge_status_path, principal: FORGE_ADMIN_ACCOUNT)

    assert_equal "not_workspace_admin", response.parsed_body["error"]
  end

  test "an uninstalled installation's page is told so" do
    invoke(bitbucket_forge_heartbeat_path)
    Bitbucket::Forge::Installations.uninstall!(BitbucketInstallation.find_by!(forge_installation_id: @installation_id))

    invoke(bitbucket_forge_status_path, principal: FORGE_ADMIN_ACCOUNT)

    assert_response :ok
    assert_equal "uninstalled", response.parsed_body["error"]
  end
end
