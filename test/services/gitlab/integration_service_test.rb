# frozen_string_literal: true

require "test_helper"

module Gitlab
  # Sociable test for Gitlab::IntegrationService on the real DB. The only faked
  # collaborator is the app-owned GitLab boundary adapter (Gitlab::TokenService),
  # swapped for Fakes::FakeGitlabService per testing doctrine R2/R3 — the gitlab
  # gem is never stubbed here (that boundary is pinned by token_service_test).
  # Assertions target OUTCOMES: the returned Integration and its persisted state.
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def stub_token_service(fake)
      Gitlab::TokenService.stubs(:new).returns(fake)
      fake
    end

    def as_user(id, username)
      stub_token_service(Fakes::FakeGitlabService.new(user: { id: id, username: username, name: username, email: nil }))
    end

    def service(project: @project)
      Gitlab::IntegrationService.new(company: @company, connected_by: @user, project: project)
    end

    test "create verifies the token and persists an active connection named after the account" do
      fake = as_user(152, "alice")

      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = service.create(personal_access_token: " glpat-secret-token ")
      end

      assert integration.persisted?, integration.errors.full_messages.to_sentence
      assert integration.gitlab?
      assert integration.status.active?
      assert_equal "alice", integration.name
      assert_equal @project, integration.project
      assert_equal @user, integration.connected_by
      assert_equal "glpat-secret-token", integration.credentials_data["personal_access_token"]
      assert_equal 152, integration.settings["gitlab_user_id"]
      assert fake.called?(:verify_token)
    end

    test "create without a project makes a company-wide connection" do
      as_user(152, "alice")

      integration = service(project: nil).create(personal_access_token: "glpat-x")

      assert_nil integration.project_id
      assert_equal @company, integration.company
    end

    test "connecting the same account again renews its connection" do
      as_user(152, "alice")
      first = service.create(personal_access_token: "glpat-old")
      first.update_columns(status: "error", settings: first.settings.merge("error" => "stale"))

      assert_no_difference -> { Integration.count } do
        assert_equal first.id, service.create(personal_access_token: "glpat-new").id
      end

      first.reload
      assert first.status.active?
      assert_equal "glpat-new", first.credentials_data["personal_access_token"]
      assert_nil first.settings["error"]
    end

    test "another account gets a connection of its own" do
      as_user(152, "alice")
      service.create(personal_access_token: "glpat-alice")
      as_user(7, "bob")

      assert_difference -> { Integration.count }, 1 do
        service.create(personal_access_token: "glpat-bob")
      end
    end

    test "the same account in another project is a separate connection" do
      as_user(152, "alice")
      service.create(personal_access_token: "glpat-a")
      other = create(:project, company: @company, owner: @user)

      assert_difference -> { Integration.count }, 1 do
        service(project: other).create(personal_access_token: "glpat-a")
      end
    end

    # Rows saved before the account id was recorded.
    test "a connection made before the account was recorded is renewed by its username" do
      legacy = create(:integration, :gitlab, :active, company: @company, project: @project, name: "alice")
      as_user(152, "alice")

      assert_no_difference -> { Integration.count } do
        assert_equal legacy.id, service.create(personal_access_token: "glpat-new").id
      end
      assert_equal 152, legacy.reload.settings["gitlab_user_id"]
    end

    test "a row a failed attempt left behind is taken over by the next connect" do
      failed = create(:integration, :gitlab, :error, company: @company, project: @project, name: "GitLab (unverified)")
      as_user(152, "alice")

      assert_no_difference -> { Integration.count } do
        assert_equal failed.id, service.create(personal_access_token: "glpat-new").id
      end
      assert_equal "alice", failed.reload.name
      assert failed.status.active?
    end

    test "a token GitLab refuses saves nothing" do
      fake = stub_token_service(
        Fakes::FakeGitlabService.new(
          verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab rejected this token. It is mistyped, expired or revoked.")
        )
      )

      error = nil
      assert_no_difference -> { Integration.count } do
        error = assert_raises(Gitlab::IntegrationService::ConnectionError) do
          service.create(personal_access_token: "glpat-bad")
        end
      end

      assert_equal "not_authorized", error.code
      assert_match(/GitLab rejected this token/, error.message)
      assert fake.called?(:verify_token)
    end

    test "GitLab being unreachable saves nothing and says so" do
      stub_token_service(
        Fakes::FakeGitlabService.new(
          verify_error: Gitlab::TokenService::ConnectionError.new("Could not reach GitLab at https://gitlab.example.com/api/v4 (SocketError).")
        )
      )

      error = nil
      assert_no_difference -> { Integration.count } do
        error = assert_raises(Gitlab::IntegrationService::ConnectionError) do
          service.create(personal_access_token: "glpat-x")
        end
      end

      assert_equal "unreachable", error.code
      assert_match(/Could not reach GitLab/, error.message)
    end

    test "a blank token is refused without asking GitLab" do
      fake = as_user(152, "alice")

      error = assert_raises(Gitlab::IntegrationService::ConnectionError) do
        service.create(personal_access_token: "  ")
      end

      assert_equal "validation_failed", error.code
      assert_not fake.called?(:verify_token)
    end

    test "replace_token swaps the token on the same row and makes it active again" do
      as_user(152, "alice")
      integration = service.create(personal_access_token: "glpat-old")
      integration.update_columns(status: "error", settings: integration.settings.merge("error" => "stale"))

      service.replace_token(integration.reload, personal_access_token: "glpat-new")

      integration.reload
      assert integration.status.active?
      assert_equal "glpat-new", integration.credentials_data["personal_access_token"]
      assert_nil integration.settings["error"]
    end

    test "replace_token keeps the current token when GitLab refuses the new one" do
      as_user(152, "alice")
      integration = service.create(personal_access_token: "glpat-old")
      stub_token_service(Fakes::FakeGitlabService.new(verify_error: Gitlab::TokenService::AuthenticationError.new("nope")))

      assert_raises(Gitlab::IntegrationService::ConnectionError) do
        service.replace_token(integration, personal_access_token: "glpat-bad")
      end

      integration.reload
      assert integration.status.active?
      assert_equal "glpat-old", integration.credentials_data["personal_access_token"]
    end

    test "replace_token refuses an account another connection here already has" do
      as_user(152, "alice")
      alice = service.create(personal_access_token: "glpat-alice")
      as_user(7, "bob")
      service.create(personal_access_token: "glpat-bob")

      error = assert_raises(Gitlab::IntegrationService::ConnectionError) do
        service.replace_token(alice, personal_access_token: "glpat-bob-2")
      end

      assert_equal "already_connected", error.code
      assert_equal "glpat-alice", alice.reload.credentials_data["personal_access_token"]
    end

    test "test re-verifies the stored token and records when" do
      as_user(152, "alice")
      integration = service.create(personal_access_token: "glpat-ok")

      result = service.test(integration)

      assert_equal :active, result[:status]
      assert integration.reload.settings["last_verified_at"].present?
    end

    test "test marks the connection for attention when GitLab refuses the token" do
      as_user(152, "alice")
      integration = service.create(personal_access_token: "glpat-expired")
      stub_token_service(
        Fakes::FakeGitlabService.new(verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab rejected this token."))
      )

      result = service.test(integration)

      assert_equal :error, result[:status]
      assert_equal "not_authorized", result[:error]
      integration.reload
      assert integration.status.error?
      assert_equal Gitlab::IntegrationService::REJECTED, integration.settings["error"]
    end

    test "test leaves the connection alone when GitLab cannot be reached" do
      as_user(152, "alice")
      integration = service.create(personal_access_token: "glpat-ok")
      stub_token_service(Fakes::FakeGitlabService.new(verify_error: Gitlab::TokenService::ConnectionError.new("down")))

      result = service.test(integration)

      assert_equal "unreachable", result[:error]
      assert integration.reload.status.active?
    end
  end
end
