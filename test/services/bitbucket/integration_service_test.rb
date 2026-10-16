# frozen_string_literal: true

require "test_helper"

module Bitbucket
  # Sociable test on the real DB; the only fake is the Bitbucket::Api seam.
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      with_bitbucket_settings
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @bitbucket = stub_bitbucket!
    end

    def service = IntegrationService.new(company: @company, connected_by: @user, project: @project)

    def as_user
      @bitbucket.user = { uuid: "{4a5b6c7d-0000-4000-8000-0000000000aa}", account_id: "557058:ada",
                          display_name: "Ada Lovelace", nickname: "ada" }
    end

    test "an access token has no user: it is checked by reading the workspace and saved as a bot" do
      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = service.create(workspace: " Acme ", token: " bb-token ")
      end

      assert integration.bitbucket_token?
      assert integration.status.active?
      assert_equal "acme", integration.name
      assert_equal "bb-token", integration.credentials_data["token"]
      assert_equal({ "auth_mode" => "token", "token_kind" => "access_token", "workspace_uuid" => FakeBitbucket::Api::WORKSPACE_UUID,
                     "workspace_slug" => "acme" }, integration.settings)
      assert_equal @project, integration.project
    end

    test "an API token is a person: named after them, its account recorded" do
      as_user

      integration = service.create(workspace: "acme", token: "api-token")

      assert_equal "api_token", integration.bitbucket_token_kind
      assert_equal "acme (Ada Lovelace)", integration.name
      assert_equal "{4a5b6c7d-0000-4000-8000-0000000000aa}", integration.settings["account_uuid"]
      assert_equal "x-bitbucket-api-token-auth", CredentialProvider.new(integration).credential.git_username
    end

    test "connecting the same workspace with an access token again renews that connection" do
      first = service.create(workspace: "acme", token: "old")
      first.update_columns(status: "error", settings: first.settings.merge("error" => "stale"))

      assert_no_difference -> { Integration.count } do
        assert_equal first.id, service.create(workspace: "acme", token: "new").id
      end
      first.reload
      assert first.status.active?
      assert_equal "new", first.credentials_data["token"]
      assert_nil first.settings["error"]
    end

    test "a token Bitbucket refuses is never saved" do
      @bitbucket.fail_on(:first_repository, Error::NotAuthorized.new("nope"))

      error = assert_no_difference(-> { Integration.count }) do
        assert_raises(IntegrationService::ConnectionError) { service.create(workspace: "acme", token: "bad") }
      end
      assert_equal "not_authorized", error.code
    end

    test "a token that reaches nothing in the workspace is refused" do
      @bitbucket.workspaces = {}

      error = assert_raises(IntegrationService::ConnectionError) { service.create(workspace: "acme", token: "t") }
      assert_equal "not_authorized", error.code
      assert_match(/cannot see the Bitbucket workspace acme/, error.message)
    end

    test "an unreachable Bitbucket says so and saves nothing" do
      @bitbucket.fail_on(:current_user, Error.new("down", code: "timeout"))

      error = assert_raises(IntegrationService::ConnectionError) { service.create(workspace: "acme", token: "t") }
      assert_equal "unreachable", error.code
    end

    test "a workspace that is not a workspace ID is refused before anything is asked" do
      error = assert_raises(IntegrationService::ConnectionError) { service.create(workspace: "acme/api", token: "t") }

      assert_equal "invalid_workspace", error.code
      assert_empty @bitbucket.calls
    end

    test "replacing the token keeps the row and its repositories" do
      integration = service.create(workspace: "acme", token: "old")

      replaced = service.replace_token(integration, token: "new")

      assert_equal integration.id, replaced.id
      assert_equal "new", replaced.reload.credentials_data["token"]
    end

    test "a replacement token for another workspace is refused" do
      integration = service.create(workspace: "acme", token: "old")
      @bitbucket.workspaces["acme"] = { uuid: "{00000000-0000-4000-8000-000000000999}", slug: "acme", name: "Acme" }
      @bitbucket.repository_list.each { |repo| repo[:workspace_uuid] = "{00000000-0000-4000-8000-000000000999}" }

      error = assert_raises(IntegrationService::ConnectionError) { service.replace_token(integration, token: "other") }
      assert_equal "wrong_workspace", error.code
      assert_equal "old", integration.reload.credentials_data["token"]
    end

    test "an app connection has no token to replace" do
      with_bitbucket_settings(app_mode: true)
      integration = create(:integration, :bitbucket_app, :active, company: @company, project: @project)

      error = assert_raises(IntegrationService::ConnectionError) { service.replace_token(integration, token: "x") }
      assert_equal "validation_failed", error.code
    end

    test "test marks the connection only when Bitbucket refuses the token" do
      integration = service.create(workspace: "acme", token: "t")

      assert_equal({ status: :active }, service.test(integration))

      @bitbucket.fail_on(:first_repository, Error.new("down", code: "timeout"))
      assert_equal "unreachable", service.test(integration)[:error]
      assert integration.reload.status.active?

      @bitbucket.fail_on(:first_repository, Error::NotAuthorized.new("revoked"))
      assert_equal "not_authorized", service.test(integration)[:error]
      assert integration.reload.status.error?
      assert_equal IntegrationService::REJECTED, integration.settings["error"]
    end

    test "test of an app connection reports a silent app without recording it" do
      with_bitbucket_settings(app_mode: true)
      integration = create(:integration, :bitbucket_app, :active, company: @company, project: @project)
      integration.bitbucket_installation.clear_token!

      result = service.test(integration)

      assert_equal "integration_unavailable", result[:error]
      assert integration.reload.status.active?
    end
  end
end
