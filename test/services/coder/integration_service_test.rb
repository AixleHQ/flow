# frozen_string_literal: true

require "test_helper"

module Coder
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      resolve_hosts_publicly!
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
    end

    def stub_users_me(status: 200, body: { id: "user-uuid", username: "alice", email: "alice@example.com" })
      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def service(project: nil)
      Coder::IntegrationService.new(company: @company, connected_by: @user, project: project)
    end

    def connect(project: nil, token: "tok-1")
      service(project: project).create(coder_url: "https://coder.example.com", session_token: token, lock_ttl_minutes: 60)
    end

    def assert_refused(code)
      error = nil
      assert_no_difference -> { Integration.count } do
        error = assert_raises(Coder::IntegrationService::ConnectionError) { yield }
      end
      assert_equal code, error.code
      error
    end

    test "happy path: persists active integration with username and settings" do
      stub_users_me

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com",
        session_token: "tok-1",
        default_template: "aws-ec2-spot-v2",
        machine_prefix: "aixle-staging",
        lock_ttl_minutes: 45
      )

      assert integration.persisted?
      assert_equal "active", integration.status.to_s
      assert_equal "Coder (alice)", integration.name
      assert_equal "https://coder.example.com", integration.credentials_data["coder_url"]
      assert_equal "tok-1", integration.credentials_data["session_token"]
      assert_equal "user-uuid", integration.credentials_data["user_id"]
      assert_equal "alice", integration.settings["coder_username"]
      assert_equal "alice@example.com", integration.settings["coder_user_email"]
      assert_equal "aws-ec2-spot-v2", integration.settings["default_template"]
      assert_equal "aixle-staging", integration.settings["machine_prefix"]
      assert_equal 45, integration.settings["lock_ttl_minutes"]
    end

    test "happy path: optional fields default to nil when blank" do
      stub_users_me

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert integration.active?
      assert_equal 60, integration.settings["lock_ttl_minutes"]
      assert_nil integration.settings["default_template"]
      assert_nil integration.settings["machine_prefix"]
    end

    test "sad path: missing lock_ttl_minutes saves nothing and calls no HTTP" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1")
      end

      assert_match(/Lock TTL minutes is required/, error.message)
    end

    test "sad path: zero or negative lock_ttl_minutes is rejected" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 0)
      end

      assert_match(/Lock TTL minutes is required/, error.message)
    end

    test "URL is normalized (trim + chomp trailing slash)" do
      stub_users_me

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "  https://coder.example.com/  ",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert_equal "https://coder.example.com", integration.credentials_data["coder_url"]
    end

    test "sad path: a token Coder refuses saves nothing" do
      stub_users_me(status: 401)

      error = assert_refused("not_authorized") { connect(token: "bad-token") }

      assert_match(/HTTP 401/, error.message)
    end

    test "sad path: Coder failing to answer saves nothing" do
      stub_users_me(status: 502)

      assert_refused("unreachable") { connect }
    end

    test "allows an http Coder URL" do
      stub_request(:get, "http://coder.example.com/api/v2/users/me").to_return(
        status: 200,
        body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "http://coder.example.com",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert integration.persisted?
      assert_equal "active", integration.status.to_s
      assert_equal "http://coder.example.com", integration.credentials_data["coder_url"]
    end

    test "allows a trusted internal kubernetes service URL for Coder" do
      stub_request(:get, "http://coder.coder.svc.cluster.local/api/v2/users/me").to_return(
        status: 200,
        body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      UrlSafetyValidator.stubs(:trusted_hosts).returns([ "coder.coder.svc.cluster.local" ])
      Resolv.stubs(:getaddresses).with("coder.coder.svc.cluster.local").returns([ "10.0.0.5" ])

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "http://coder.coder.svc.cluster.local",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert integration.persisted?
      assert_equal "active", integration.status.to_s
      assert_equal "http://coder.coder.svc.cluster.local", integration.credentials_data["coder_url"]
    end

    test "sad path: localhost URL rejected before HTTP call" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://localhost", session_token: "tok-1", lock_ttl_minutes: 60)
      end

      assert_match(/internal services/, error.message)
    end

    test "sad path: private CIDR URL rejected before HTTP call" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://10.0.0.5", session_token: "tok-1", lock_ttl_minutes: 60)
      end

      assert_match(/private or internal/, error.message)
    end

    test "scoping: project-scoped integration is persisted with project_id" do
      stub_users_me
      project = create(:project, company: @company, owner: @user)

      integration = Coder::IntegrationService.new(
        company: @company, connected_by: @user, project: project
      ).create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60)

      assert integration.active?
      assert_equal project.id, integration.project_id
    end

    test "connecting the same URL as the same account renews that connection" do
      stub_users_me
      project = create(:project, company: @company, owner: @user)
      first = service(project: project).create(
        coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60,
        default_template: "tpl", machine_prefix: "aixle-prod"
      )

      second = nil
      assert_no_difference -> { Integration.count } do
        second = service(project: project).create(
          coder_url: "https://coder.example.com/", session_token: "tok-2", lock_ttl_minutes: 90
        )
      end

      assert_equal first.id, second.id
      first.reload
      assert_equal "tok-2", first.credentials_data["session_token"]
      assert_equal 90, first.coder_lock_ttl_minutes
      # Left blank on the form: kept, not cleared — a blank prefix would widen the pool.
      assert_equal "tpl", first.coder_default_template
      assert_equal "aixle-prod", first.coder_machine_prefix
    end

    test "a project cannot get a second active Coder connection" do
      project = create(:project, company: @company, owner: @user)
      create(:integration, :coder, :active, company: @company, project: project, connected_by: @user,
                                            name: "Coder (bob)")
      stub_users_me

      error = assert_refused("already_connected") { connect(project: project) }

      assert_match(/Coder \(bob\) is already connected here/, error.message)
    end

    test "a connection in error does not block connecting another account" do
      project = create(:project, company: @company, owner: @user)
      create(:integration, :coder, :error, company: @company, project: project, connected_by: @user)
      stub_users_me

      assert_difference -> { Integration.count }, 1 do
        assert connect(project: project).active?
      end
    end

    test "a row a failed attempt left for the same URL is taken over" do
      project = create(:project, company: @company, owner: @user)
      failed = create(:integration, :coder, :error, company: @company, project: project, connected_by: @user,
                                                    name: "Coder (unverified)")
      failed.update!(credentials_data: { coder_url: "https://coder.example.com", session_token: "bad" })
      stub_users_me

      assert_no_difference -> { Integration.count } do
        assert_equal failed.id, connect(project: project).id
      end
      failed.reload
      assert failed.active?
      assert_equal "Coder (alice)", failed.name
      assert_nil failed.settings["error"]
    end

    test "replace_token swaps the session token in place" do
      stub_users_me
      integration = connect
      integration.update_columns(status: "error", settings: integration.settings.merge("error" => "stale"))

      service.replace_token(integration.reload, session_token: "tok-new")

      integration.reload
      assert integration.active?
      assert_equal "tok-new", integration.credentials_data["session_token"]
      assert_equal "https://coder.example.com", integration.coder_url
      assert_equal 60, integration.coder_lock_ttl_minutes
      assert_nil integration.settings["error"]
    end

    test "replace_token keeps the current token when Coder refuses the new one" do
      stub_users_me
      integration = connect
      stub_users_me(status: 401)

      assert_raises(Coder::IntegrationService::ConnectionError) do
        service.replace_token(integration, session_token: "tok-bad")
      end

      assert_equal "tok-1", integration.reload.credentials_data["session_token"]
      assert integration.active?
    end

    test "test marks the connection for attention when Coder refuses the token" do
      stub_users_me
      integration = connect
      stub_users_me(status: 401)

      result = service.test(integration)

      assert_equal "not_authorized", result[:error]
      integration.reload
      assert integration.error?
      assert_equal Coder::IntegrationService::REJECTED, integration.settings["error"]
    end

    test "test leaves the connection alone when Coder does not answer" do
      stub_users_me
      integration = connect
      stub_request(:get, "https://coder.example.com/api/v2/users/me").to_timeout

      result = service.test(integration)

      assert_equal "unreachable", result[:error]
      assert integration.reload.active?
    end

    test "test brings a repaired connection back to active" do
      stub_users_me
      integration = connect
      integration.update_columns(status: "error", settings: integration.settings.merge("error" => "stale"))

      result = service.test(integration.reload)

      assert_equal :active, result[:status]
      integration.reload
      assert integration.active?
      assert_nil integration.settings["error"]
      assert integration.settings["last_verified_at"].present?
    end

    test "update_settings edits the allocator settings and leaves credentials alone" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      credentials_before = integration.credentials_data

      Coder::IntegrationService.new(company: @company, connected_by: @user).update_settings(
        integration: integration, default_template: "aws-ec2-spot-v1",
        machine_prefix: "aixle-prod", lock_ttl_minutes: "90"
      )

      integration.reload
      assert_equal "aws-ec2-spot-v1", integration.coder_default_template
      assert_equal "aixle-prod", integration.coder_machine_prefix
      assert_equal 90, integration.coder_lock_ttl_minutes
      assert_equal credentials_before, integration.credentials_data
      # Identity written at connect time survives an edit.
      assert_equal "test-user", integration.settings["coder_username"]
    end

    test "update_settings treats a blank template or prefix as a removal" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      integration.update!(
        settings: integration.settings.merge("default_template" => "tpl", "machine_prefix" => "aixle-prod")
      )

      Coder::IntegrationService.new(company: @company, connected_by: @user).update_settings(
        integration: integration, default_template: "  ", machine_prefix: nil, lock_ttl_minutes: 120
      )

      integration.reload
      assert_nil integration.coder_default_template
      assert_nil integration.coder_machine_prefix
    end

    test "update_settings rejects a non-positive or missing lock TTL" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      service = Coder::IntegrationService.new(company: @company, connected_by: @user)

      [ "0", "-5", "abc", nil, "" ].each do |bad|
        error = assert_raises(Coder::IntegrationService::ConfigurationError) do
          service.update_settings(integration: integration, lock_ttl_minutes: bad)
        end
        assert_match(/Lock TTL minutes must be a positive number/, error.message)
      end

      assert_equal 60, integration.reload.coder_lock_ttl_minutes
    end

    test "update_settings refuses a non-Coder integration" do
      integration = create(:integration, :gitlab, company: @company, connected_by: @user)

      error = assert_raises(Coder::IntegrationService::ConfigurationError) do
        Coder::IntegrationService.new(company: @company, connected_by: @user).update_settings(
          integration: integration, lock_ttl_minutes: 120
        )
      end
      assert_match(/Only Coder integrations have editable settings/, error.message)
    end
  end
end
