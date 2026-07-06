# frozen_string_literal: true

require "test_helper"

# Request test for the deployment-wide Slack OAuth callback
# (GET /integrations/slack/oauth/callback -> Web::Integrations::SlackOauthController#callback).
#
# The callback (a) verifies the signed, single-use `state`, (b) confirms it pins
# the initiating user (anti-CSRF), (c) resolves the project the state names, then
# (d) hands the ?code to Slack::IntegrationService, which exchanges it for a bot
# token via Slack::Client and persists a company-wide Slack integration.
#
# The Slack boundary is faked with the canonical seam (`stub_slack_client!` from
# SlackTestHelper): Slack::Client.exchange_code hits the in-memory FakeSlackClient,
# so nothing touches the network. State is exercised through the REAL flow
# (Slack::Oauth.sign_state / consume_state_nonce), which round-trips the nonce
# through Rails.cache — the test stubs a live MemoryStore because the test env's
# :null_store would otherwise drop the nonce and make every link look replayed.
class Web::Integrations::SlackOauthTest < ActionDispatch::IntegrationTest
  setup do
    # Real cache so sign_state's nonce survives to consume_state_nonce; the test
    # env is :null_store (write is a no-op, delete returns false => "already used").
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)

    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)

    # Route Slack::Client.exchange_code to the in-memory fake; tailor the workspace
    # identity so the persisted install is asserted against concrete values.
    @slack = stub_slack_client!
    @slack.team_id   = "T0SLACKONE"
    @slack.team_name = "Acme HQ"
    @slack.bot_token = "xoxb-acme-0001-bot"
  end

  test "success: valid code + state exchanges a bot token, persists the Slack install, and redirects to the project" do
    state = Slack::Oauth.sign_state(@project, @user)

    assert_difference("Integration.count", 1) do
      get slack_oauth_callback_path, params: { code: "valid-oauth-code", state: state }
    end

    assert_response :redirect
    assert_redirected_to company_project_integrations_path(@project)

    # The code was actually exchanged through the faked Slack boundary.
    assert_equal "valid-oauth-code", @slack.oauth_exchanges.last[:code]

    integration = Integration.last
    assert integration.slack?
    assert integration.active?
    assert_nil integration.project_id, "Slack installs are company-wide (project_id: nil)"
    assert_equal @company.id, integration.company_id
    assert_equal @user.id, integration.connected_by_id
    assert_equal "Acme HQ", integration.name
    assert_equal "T0SLACKONE", integration.settings["team_id"]
    assert_equal "Acme HQ", integration.settings["team_name"]
    assert_equal "xoxb-acme-0001-bot", integration.credentials_data["bot_token"]
  end

  test "reconnecting the same workspace updates the existing install instead of creating a duplicate" do
    get slack_oauth_callback_path, params: { code: "code-1", state: Slack::Oauth.sign_state(@project, @user) }
    assert_equal 1, @company.integrations.where(provider: :slack).count
    original = Integration.last

    # A second authorization (fresh nonce) for the same team_id reuses the record.
    @slack.team_name = "Acme HQ Renamed"
    assert_no_difference("Integration.count") do
      get slack_oauth_callback_path, params: { code: "code-2", state: Slack::Oauth.sign_state(@project, @user) }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal original.id, Integration.last.id
    assert_equal "Acme HQ Renamed", original.reload.name
  end

  test "invalid/expired state redirects to root and creates no integration" do
    assert_no_difference("Integration.count") do
      get slack_oauth_callback_path, params: { code: "valid-oauth-code", state: "not-a-real-state" }
    end

    assert_redirected_to root_path
    assert_equal "Invalid or expired Slack authorization", flash[:alert]
    assert_empty @slack.oauth_exchanges, "no code exchange when the state fails verification"
  end

  test "state that pins a different user is rejected (anti-CSRF) and creates no integration" do
    other_user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    state = Slack::Oauth.sign_state(@project, other_user)

    assert_no_difference("Integration.count") do
      get slack_oauth_callback_path, params: { code: "valid-oauth-code", state: state }
    end

    assert_redirected_to root_path
    assert_equal "Slack authorization did not match your session", flash[:alert]
    assert_empty @slack.oauth_exchanges
  end

  test "user cancel (error param) redirects to the project without exchanging a code" do
    state = Slack::Oauth.sign_state(@project, @user)

    assert_no_difference("Integration.count") do
      get slack_oauth_callback_path, params: { state: state, error: "access_denied" }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "Slack connection was cancelled", flash[:alert]
    assert_empty @slack.oauth_exchanges
  end

  test "a replayed authorization link is rejected (single-use nonce) and creates no second integration" do
    state = Slack::Oauth.sign_state(@project, @user)

    get slack_oauth_callback_path, params: { code: "valid-oauth-code", state: state }
    assert_equal 1, Integration.count

    # Same state string again: the nonce was consumed on first use.
    assert_no_difference("Integration.count") do
      get slack_oauth_callback_path, params: { code: "valid-oauth-code", state: state }
    end

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal "This Slack authorization link was already used", flash[:alert]
  end
end
