# frozen_string_literal: true

require "test_helper"

module Slack
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    def service
      Slack::IntegrationService.new(company: @company, connected_by: @user, project: @project)
    end

    # Route Slack::Client onto the one canonical in-memory fake and tailor the
    # OAuth exchange response the code under test consumes. Returns the fake so a
    # test can assert on its recorded calls / mutate the canned values between
    # successive exchanges.
    def stub_slack_oauth(team_id: "T123", team_name: "Acme HQ")
      fake = stub_slack_client!
      fake.team_id     = team_id
      fake.team_name   = team_name
      fake.bot_token   = "xoxb-abc"
      fake.bot_user_id = "U999"
      fake.scope       = "chat:write,files:read"
      fake
    end

    test "create_from_oauth persists an active install with the bot token and routable team_id" do
      fake = stub_slack_oauth

      integration = service.create_from_oauth(code: "code-1")

      assert integration.persisted?
      assert integration.active?
      assert_equal "Acme HQ", integration.name
      assert_equal "xoxb-abc", integration.credentials_data["bot_token"]
      assert_equal "U999", integration.credentials_data["bot_user_id"]
      assert_equal "T123", integration.credentials_data["team_id"]
      # team_id is mirrored into settings (non-secret) so inbound events route without decrypting.
      assert_equal "T123", integration.settings["team_id"]
      assert_equal "Acme HQ", integration.settings["team_name"]
      # what people type to mention the bot, for the channel connect dialog
      assert_equal "Aixle Flow", integration.settings["bot_name"]
      assert_equal [ { token: "xoxb-abc" } ], fake.auth_tests
      # the OAuth code was exchanged through the Slack boundary exactly once
      assert_equal 1, fake.oauth_exchanges.size
      assert_equal "code-1", fake.oauth_exchanges.last[:code]
    end

    # A refusal used to leave a company-wide error row each time, which only a
    # company admin could remove.
    test "create_from_oauth saves nothing when Slack rejects the code" do
      # The fake always returns a successful exchange, so the rejection path stays
      # on a Mocha stub (the canonical fake has no seam to raise Slack::Client::Error).
      Slack::Client.expects(:exchange_code).raises(Slack::Client::Error.new("invalid_code"))

      integration = nil
      assert_no_difference -> { Integration.count } do
        integration = service.create_from_oauth(code: "bad")
      end

      assert_not integration.persisted?
      assert integration.error?
      assert_match(/invalid_code/, integration.settings["error"])
    end

    test "create_from_oauth saves nothing when Slack returns no workspace id" do
      stub_slack_oauth(team_id: "")

      integration = nil
      assert_no_difference -> { Integration.count } do
        integration = service.create_from_oauth(code: "code-1")
      end

      assert integration.error?
      assert_match(/workspace id/, integration.settings["error"])
    end

    test "a refused reconnect leaves the existing install as it was" do
      fake = stub_slack_oauth(team_id: "T123")
      installed = service.create_from_oauth(code: "c1")
      fake.team_id = ""

      assert service.create_from_oauth(code: "c2").error?

      installed.reload
      assert installed.active?
      assert_nil installed.settings["error"]
      assert_equal 1, @company.integrations.where(provider: :slack).count
    end

    test "a second company connecting the same workspace shares it: one bot token, and the endpoint keeps its install" do
      other = create(:user, :with_company)
      first = Slack::IntegrationService.new(company: other.companies.first, connected_by: other)
      stub_slack_oauth(team_id: "T123").bot_token = "xoxb-first"
      theirs = first.create_from_oauth(code: "c1")
      fake_slack.bot_token = "xoxb-second"

      ours = service.create_from_oauth(code: "c2")

      assert ours.persisted? && ours.active?, ours.settings["error"].to_s
      assert_equal theirs.chat_workspace, ours.chat_workspace
      assert_equal [ "xoxb-second" ] * 2, [ theirs.reload, ours ].map { |i| i.credentials_data["bot_token"] }
      endpoint = WebhookEndpoint.find_by!(slug: "slack-team-T123")
      assert_equal [ theirs.id, ours.chat_workspace_id ], endpoint.config.values_at("integration_id", "chat_workspace_id")
    end

    test "reinstalling the app after Slack removed it switches every company of the workspace back on" do
      other = create(:user, :with_company)
      stub_slack_oauth(team_id: "T123")
      theirs = Slack::IntegrationService.new(company: other.companies.first, connected_by: other).create_from_oauth(code: "c1")
      theirs.update!(status: :inactive)

      service.create_from_oauth(code: "c2")

      assert theirs.reload.active?
      assert_equal "active", theirs.chat_workspace.status
    end

    # Once uninstalled from Slack, or removed from Aixle, the other company's
    # endpoint is disabled — and a disabled endpoint claims nothing.
    test "a workspace another company no longer has connected can be connected here" do
      other = create(:user, :with_company)
      endpoint = create(:webhook_endpoint, slug: "slack-team-T123", provider: :slack, enabled: false,
                                           verification_strategy: :slack_v0, company: other.companies.first,
                                           created_by: other, config: { "team_id" => "T123" })
      stub_slack_oauth(team_id: "T123")

      integration = service.create_from_oauth(code: "c")

      assert integration.active?, integration.settings["error"]
      assert_equal @company.id, endpoint.reload.company_id
      assert endpoint.enabled?
    end

    test "removing the install releases the workspace" do
      stub_slack_oauth(team_id: "T777")
      integration = service.create_from_oauth(code: "c")
      endpoint = WebhookEndpoint.find_by!(slug: "slack-team-T777")

      integration.destroy!

      assert_not endpoint.reload.enabled?
    end

    test "reconnecting the same workspace updates the existing install instead of duplicating" do
      fake = stub_slack_oauth(team_id: "T1", team_name: "Acme")

      first = service.create_from_oauth(code: "c1")
      assert first.active?

      # Same workspace reconnects with a renamed team on the next exchange.
      fake.team_name = "Acme Renamed"

      assert_no_difference -> { Integration.where(provider: :slack).count } do
        second = service.create_from_oauth(code: "c2")
        assert_equal first.id, second.id
        assert_equal "Acme Renamed", second.reload.name
      end
    end

    test "the install is company-scoped (no project binding) so all projects share it" do
      stub_slack_oauth

      integration = service.create_from_oauth(code: "c")

      assert_nil integration.project_id
      assert_equal @company.id, integration.company_id
      endpoint = WebhookEndpoint.find_by(slug: "slack-team-T123")
      assert_nil endpoint.project_id
      assert_equal @company.id, endpoint.company_id
    end

    test "a company can connect several different workspaces" do
      fake = stub_slack_oauth(team_id: "T1", team_name: "WS One")

      first = service.create_from_oauth(code: "c1")

      # A second, distinct workspace exchanges next.
      fake.team_id   = "T2"
      fake.team_name = "WS Two"
      second = service.create_from_oauth(code: "c2")

      assert_not_equal first.id, second.id
      teams = Integration.where(provider: :slack, company: @company).map { |i| i.settings["team_id"] }
      assert_equal %w[T1 T2], teams.sort
    end
  end
end
