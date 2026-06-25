# frozen_string_literal: true

require "test_helper"

module Slack
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.company
      @project = create(:project, owner: @user, company: @company)
    end

    def service
      Slack::IntegrationService.new(company: @company, connected_by: @user, project: @project)
    end

    def oauth_response(team_id: "T123", team_name: "Acme HQ")
      {
        "ok" => true,
        "access_token" => "xoxb-abc",
        "bot_user_id" => "U999",
        "scope" => "chat:write,files:read",
        "team" => { "id" => team_id, "name" => team_name }
      }
    end

    test "create_from_oauth persists an active install with the bot token and routable team_id" do
      Slack::Client.expects(:exchange_code).returns(oauth_response)

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
    end

    test "create_from_oauth records an error integration when Slack rejects the code" do
      Slack::Client.expects(:exchange_code).raises(Slack::Client::Error.new("invalid_code"))

      integration = service.create_from_oauth(code: "bad")

      assert integration.persisted?
      assert integration.error?
      assert_match(/invalid_code/, integration.settings["error"])
    end

    test "create_from_oauth errors when Slack returns no workspace id" do
      Slack::Client.expects(:exchange_code).returns(oauth_response(team_id: ""))

      integration = service.create_from_oauth(code: "code-1")

      assert integration.error?
      assert_match(/workspace id/, integration.settings["error"])
    end

    test "rejects a workspace already connected to another company (no hijack)" do
      other = create(:user, :with_company)
      create(:webhook_endpoint, slug: "slack-team-T123", provider: :slack,
        verification_strategy: :slack_v0, company: other.company, created_by: other,
        config: { "team_id" => "T123" })

      Slack::Client.expects(:exchange_code).returns(oauth_response(team_id: "T123"))

      integration = service.create_from_oauth(code: "c")

      assert integration.error?
      assert_match(/another organization/, integration.settings["error"])
    end

    test "reconnecting the same workspace updates the existing install instead of duplicating" do
      Slack::Client.stubs(:exchange_code).returns(
        oauth_response(team_id: "T1", team_name: "Acme"),
        oauth_response(team_id: "T1", team_name: "Acme Renamed")
      )

      first = service.create_from_oauth(code: "c1")
      assert first.active?

      assert_no_difference -> { Integration.where(provider: :slack).count } do
        second = service.create_from_oauth(code: "c2")
        assert_equal first.id, second.id
        assert_equal "Acme Renamed", second.reload.name
      end
    end
  end
end
