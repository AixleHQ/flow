# frozen_string_literal: true

require "test_helper"

class Linear::IntegrationServiceTest < ActiveSupport::TestCase
  ENG = FakeLinear::Api::ENG
  OPS = FakeLinear::Api::OPS

  setup do
    with_linear_oauth_app
    @linear = stub_linear!
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
    @service = Linear::IntegrationService.new(company: company, connected_by: @user, project: @project)
  end

  def stub_code_exchange
    stub_request(:post, "https://api.linear.app/oauth/token").with(body: hash_including("grant_type" => "authorization_code"))
      .to_return(status: 200, body: { access_token: "at-1", refresh_token: "rt-1", expires_in: 86_399 }.to_json)
  end

  test "an API key connects to the teams picked, each becoming a tracker" do
    integration = @service.connect_api_key(api_key: " lin_api_x ", team_ids: [ ENG ], dedicated_identity: "true")

    assert_equal [ "active", "Linear · Acme" ], [ integration.status.to_s, integration.name ]
    assert_equal({ "auth_mode" => "api_key", "organization_id" => FakeLinear::Api::ORGANIZATION, "url_key" => "acme",
                   "dedicated_identity" => true, "linear_teams" => [ { "id" => ENG, "key" => "ENG", "name" => "Engineering" } ] },
                 integration.settings.slice("auth_mode", "organization_id", "url_key", "dedicated_identity", "linear_teams"))
    assert_equal "lin_api_x", integration.credentials_data["api_key"]
    assert_equal({ "id" => FakeLinear::Api::BOT_ID, "name" => "Aixle Bot", "login" => "aixle" }, integration.settings["tracker_identity"])
    tracker = integration.project_trackers.sole
    assert_equal [ ENG, "ENG", "engineering", true ], [ tracker.external_scope_id, tracker.external_scope_key, tracker.handle, tracker.primary ]
    assert_empty integration.tracker_subscriptions, "no webhook until a tracker trigger waits for one"
  end

  test "reconnecting the workspace renews that connection in place and follows the teams" do
    first = @service.connect_api_key(api_key: "a", team_ids: [ ENG, OPS ])

    second = @service.connect_api_key(api_key: "b", team_ids: [ OPS ])

    assert_equal first.id, second.id
    assert_equal "b", second.credentials_data["api_key"]
    assert_equal({ ENG => "detached", OPS => "active" }, second.project_trackers.pluck(:external_scope_id, :status).to_h)
    assert_equal false, second.settings["dedicated_identity"] # rubocop:disable Minitest/RefuteFalse
  end

  test "teams the key cannot see, or none, are refused" do
    assert_raises(Linear::IntegrationService::ConfigurationError) { @service.connect_api_key(api_key: "a", team_ids: []) }
    error = assert_raises(Linear::IntegrationService::ConfigurationError) { @service.connect_api_key(api_key: "a", team_ids: [ "t-x" ]) }
    assert_match(/cannot see 1/, error.message)
  end

  test "the OAuth callback leaves a pending connection until its teams are picked, then the app delivers its events" do
    stub_code_exchange

    pending = @service.connect_oauth(code: "c0de")

    assert_equal [ "inactive", "oauth", true ], [ pending.status.to_s, pending.settings["auth_mode"], pending.settings["dedicated_identity"] ]
    assert_equal [ "at-1", "rt-1" ], pending.credentials_data.values_at("access_token", "refresh_token")

    active = @service.configure(pending, team_ids: [ ENG ], dedicated_identity: "false")

    assert_equal "active", active.status.to_s
    assert_equal true, active.settings["dedicated_identity"], "the app always acts as itself" # rubocop:disable Minitest/AssertTruthy
    assert_equal [ "app" ], active.tracker_subscriptions.pluck(:strategy)
  end

  test "an OAuth callback for a workspace already connected renews it and keeps it active" do
    stub_code_exchange
    existing = create(:integration, :linear_oauth, :active, company: @project.company, project: @project, connected_by: @user)

    renewed = @service.connect_oauth(code: "c0de")

    assert_equal [ existing.id, "active", "at-1" ], [ renewed.id, renewed.status.to_s, renewed.credentials_data["access_token"] ]
  end

  test "test reports a team the connection can no longer see and repairs the rest" do
    integration = create(:integration, :linear, :active, company: @project.company, project: @project, connected_by: @user,
                                                         linear_teams: [ { "id" => ENG, "key" => "ENG" }, { "id" => "t-gone", "key" => "OLD" } ])

    result = @service.test(integration)

    assert_equal({ status: :active, warning: true, message: "This connection can no longer see OLD" }, result)
    assert_equal "Engineering", integration.reload.settings["linear_teams"].first["name"]
  end

  test "test puts a refused credential in error and leaves a throttled one alone" do
    integration = create(:integration, :linear, :active, company: @project.company, project: @project, connected_by: @user)
    @linear.fail_next(:identity, Trackers::Error.new("Rate limited", code: "rate_limited"))
    assert_equal :error, @service.test(integration)[:status]
    assert_equal "active", integration.reload.status.to_s

    @linear.fail_next(:identity, Trackers::Error.new("Bad key", code: "not_authorized"))
    @service.test(integration)
    assert_equal "error", integration.reload.status.to_s
  end
end
