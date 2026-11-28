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

    def stub_templates(names = %w[tpl aws-ec2-spot-v2 aws-ec2-spot-v1], status: 200)
      stub_request(:get, "https://coder.example.com/api/v2/templates")
        .to_return(status: status, body: names.map { |name| { id: SecureRandom.uuid, name: name } }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    def service(project: nil)
      Coder::IntegrationService.new(company: @company, connected_by: @user, project: project)
    end

    def connect(project: nil, token: "tok-1", **settings)
      stub_templates
      service(project: project).create(
        coder_url: "https://coder.example.com", session_token: token, lock_ttl_minutes: 60,
        **{ default_template: "tpl", machine_prefix: "aixle-prod" }.merge(settings)
      )
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
      stub_templates

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

    test "sad path: a blank default template saves nothing" do
      stub_users_me

      error = assert_refused("validation_failed") { connect(default_template: " ") }

      assert_match(/Default template is required/, error.message)
    end

    test "sad path: a template the token cannot see saves nothing" do
      stub_users_me
      stub_templates(%w[other])

      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60,
                       default_template: "tpl", machine_prefix: "aixle")
      end

      assert_match(/not one of the templates/, error.message)
    end

    test "sad path: a blank, uppercase, hyphen-edged or too long prefix saves nothing" do
      stub_users_me

      [ "", nil, "Aixle", "aixle-", "-aixle", "aixle_prod", "a" * 24 ].each do |prefix|
        error = assert_refused("validation_failed") { connect(machine_prefix: prefix) }
        assert_match(/Machine prefix is required/, error.message)
      end
    end

    test "sad path: Coder refusing the template list saves nothing" do
      stub_users_me
      stub_templates(status: 403)

      assert_refused("not_authorized") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60,
                       default_template: "tpl", machine_prefix: "aixle")
      end
    end

    test "templates lists the names the token can see, sorted" do
      stub_templates(%w[b a])

      assert_equal %w[a b], service.templates(coder_url: "https://coder.example.com/", session_token: "tok-1")
    end

    test "templates refuses a private URL before any HTTP call" do
      error = assert_raises(Coder::IntegrationService::ConnectionError) do
        service.templates(coder_url: "https://10.0.0.5", session_token: "tok-1")
      end

      assert_equal "validation_failed", error.code
    end

    test "templates_of reads the list with the stored token" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      stub_templates(%w[one two])

      assert_equal %w[one two], service.templates_of(integration)
    end

    test "sad path: missing lock_ttl_minutes saves nothing and calls no HTTP" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1",
                       default_template: "tpl", machine_prefix: "aixle")
      end

      assert_match(/Lock TTL minutes is required/, error.message)
    end

    test "sad path: zero or negative lock_ttl_minutes is rejected" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 0,
                       default_template: "tpl", machine_prefix: "aixle")
      end

      assert_match(/Lock TTL minutes is required/, error.message)
    end

    test "URL is normalized (trim + chomp trailing slash)" do
      stub_users_me
      stub_templates

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "  https://coder.example.com/  ",
        session_token: "tok-1",
        lock_ttl_minutes: 60,
        default_template: "tpl", machine_prefix: "aixle"
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
      stub_request(:get, "http://coder.example.com/api/v2/templates")
        .to_return(status: 200, body: [ { name: "tpl" } ].to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "http://coder.example.com/api/v2/users/me").to_return(
        status: 200,
        body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      integration = Coder::IntegrationService.new(company: @company, connected_by: @user).create(
        coder_url: "http://coder.example.com",
        session_token: "tok-1",
        lock_ttl_minutes: 60,
        default_template: "tpl", machine_prefix: "aixle"
      )

      assert integration.persisted?
      assert_equal "active", integration.status.to_s
      assert_equal "http://coder.example.com", integration.credentials_data["coder_url"]
    end

    test "allows a trusted internal kubernetes service URL for Coder" do
      stub_request(:get, "http://coder.coder.svc.cluster.local/api/v2/templates")
        .to_return(status: 200, body: [ { name: "tpl" } ].to_json, headers: { "Content-Type" => "application/json" })
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
        lock_ttl_minutes: 60,
        default_template: "tpl", machine_prefix: "aixle"
      )

      assert integration.persisted?
      assert_equal "active", integration.status.to_s
      assert_equal "http://coder.coder.svc.cluster.local", integration.credentials_data["coder_url"]
    end

    test "sad path: localhost URL rejected before HTTP call" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://localhost", session_token: "tok-1", lock_ttl_minutes: 60,
                       default_template: "tpl", machine_prefix: "aixle")
      end

      assert_match(/internal services/, error.message)
    end

    test "sad path: private CIDR URL rejected before HTTP call" do
      error = assert_refused("validation_failed") do
        service.create(coder_url: "https://10.0.0.5", session_token: "tok-1", lock_ttl_minutes: 60,
                       default_template: "tpl", machine_prefix: "aixle")
      end

      assert_match(/private or internal/, error.message)
    end

    test "scoping: project-scoped integration is persisted with project_id" do
      stub_users_me
      stub_templates
      project = create(:project, company: @company, owner: @user)

      integration = Coder::IntegrationService.new(
        company: @company, connected_by: @user, project: project
      ).create(coder_url: "https://coder.example.com", session_token: "tok-1", lock_ttl_minutes: 60,
               default_template: "tpl", machine_prefix: "aixle")

      assert integration.active?
      assert_equal project.id, integration.project_id
    end

    test "connecting the same URL, account and prefix again makes a new integration" do
      stub_users_me
      project = create(:project, company: @company, owner: @user)
      first = connect(project: project)

      second = nil
      assert_difference -> { Integration.count }, 1 do
        second = connect(project: project, token: "tok-2")
      end

      assert_not_equal first.id, second.id
      assert_equal "tok-1", first.reload.credentials_data["session_token"]
      assert_equal "tok-2", second.credentials_data["session_token"]
      assert first.active? && second.active?
    end

    test "two integrations of the same account and prefix coexist in one scope and across scopes" do
      stub_users_me
      project = create(:project, company: @company, owner: @user)
      other = create(:project, company: @company, owner: @user)

      assert_difference -> { Integration.count }, 3 do
        connect(project: project)
        connect(project: project)
        connect(project: other)
      end
    end

    test "a connection in error does not block connecting another account" do
      project = create(:project, company: @company, owner: @user)
      create(:integration, :coder, :error, company: @company, project: project, connected_by: @user)
      stub_users_me

      assert_difference -> { Integration.count }, 1 do
        assert connect(project: project).active?
      end
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

    test "test reactivates a connection with no check of what else the scope holds" do
      stub_users_me
      project = create(:project, company: @company, owner: @user)
      integration = connect(project: project)
      connect(project: project, token: "tok-2")
      integration.update_columns(status: "error")

      assert_equal :active, service(project: project).test(integration.reload)[:status]
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
      stub_templates

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

    test "update_settings refuses a blank template or prefix, and a template the token cannot see" do
      integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      stub_templates(%w[tpl])
      service = Coder::IntegrationService.new(company: @company, connected_by: @user)

      [ [ " ", "aixle" ], [ "tpl", nil ], [ "tpl", "Bad Prefix" ], [ "missing", "aixle" ] ].each do |template, prefix|
        error = assert_raises(Coder::IntegrationService::ConnectionError) do
          service.update_settings(integration: integration, default_template: template, machine_prefix: prefix,
                                  lock_ttl_minutes: 120)
        end
        assert_equal "validation_failed", error.code
      end

      assert_nil integration.reload.coder_default_template
    end

    test "a legacy row without template or prefix reports what it lacks, and the next save needs both" do
      legacy = create(:integration, :coder, :active, company: @company, connected_by: @user)

      assert_equal %w[default_template machine_prefix], legacy.coder_missing_settings
      legacy.update!(settings: legacy.settings.merge("default_template" => "tpl"))
      assert_equal %w[machine_prefix], legacy.coder_missing_settings
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
