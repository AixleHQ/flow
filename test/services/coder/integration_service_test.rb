# frozen_string_literal: true

require "test_helper"

module Coder
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
    end

    def stub_users_me(status: 200, body: { id: "user-uuid", username: "alice", email: "alice@example.com" })
      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
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

    test "sad path: missing lock_ttl_minutes persists record in error state without calling HTTP" do
      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com",
        session_token: "tok-1"
      )

      assert integration.persisted?
      assert_equal "error", integration.status.to_s
      assert_match(/Lock TTL minutes is required/, integration.settings["error"])
    end

    test "sad path: zero or negative lock_ttl_minutes is rejected" do
      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com",
        session_token: "tok-1",
        lock_ttl_minutes: 0
      )

      assert_equal "error", integration.status.to_s
      assert_match(/Lock TTL minutes is required/, integration.settings["error"])
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

    test "sad path: invalid token persists record in error state" do
      stub_users_me(status: 401)

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com",
        session_token: "bad-token",
        lock_ttl_minutes: 60
      )

      assert integration.persisted?
      assert_equal "error", integration.status.to_s
      assert_equal "Coder (unverified)", integration.name
      assert_match(/HTTP 401/, integration.settings["error"])
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
      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://localhost",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert integration.persisted?
      assert_equal "error", integration.status.to_s
      assert_match(/internal services/, integration.settings["error"])
    end

    test "sad path: private CIDR URL rejected before HTTP call" do
      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://10.0.0.5",
        session_token: "tok-1",
        lock_ttl_minutes: 60
      )

      assert integration.persisted?
      assert_equal "error", integration.status.to_s
      assert_match(/private or internal/, integration.settings["error"])
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

    test "allows multiple Coder integrations in the same scope" do
      stub_users_me

      first = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60
      )
      second = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "https://coder.example.com", session_token: "tok-2", lock_ttl_minutes: 60
      )

      assert first.persisted?
      assert second.persisted?
      assert_not_equal first.id, second.id
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
