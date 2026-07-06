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
    end

    def stub_token_service(fake)
      Gitlab::TokenService.stubs(:new).returns(fake)
    end

    test "create verifies the token and persists an active, company-wide integration" do
      fake = Fakes::FakeGitlabService.new(
        user: { id: 152, username: "alice", name: "Alice Smith", email: "alice@example.com" }
      )
      stub_token_service(fake)

      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = Gitlab::IntegrationService
          .new(company: @company, connected_by: @user)
          .create(personal_access_token: "glpat-secret-token")
      end

      assert integration.persisted?, integration.errors.full_messages.to_sentence
      assert integration.gitlab?
      assert integration.status.active?
      assert_equal "alice", integration.name
      assert_equal @company, integration.company
      assert_equal @user, integration.connected_by
      assert_nil integration.project
      assert_equal "glpat-secret-token", integration.credentials_data["personal_access_token"]
      assert fake.called?(:verify_token)
    end

    test "create scopes the integration to the given project" do
      project = create(:project, company: @company, owner: @user)
      stub_token_service(Fakes::FakeGitlabService.new)

      integration = Gitlab::IntegrationService
        .new(company: @company, connected_by: @user, project: project)
        .create(personal_access_token: "glpat-project-token")

      assert integration.persisted?, integration.errors.full_messages.to_sentence
      assert integration.status.active?
      assert_equal project, integration.project
      assert_equal @company, integration.company
    end

    test "create names the integration after the verified GitLab username" do
      stub_token_service(
        Fakes::FakeGitlabService.new(
          user: { id: 7, username: "bob", name: "Bob Jones", email: "bob@example.com" }
        )
      )

      integration = Gitlab::IntegrationService
        .new(company: @company, connected_by: @user)
        .create(personal_access_token: "glpat-bob")

      assert_equal "bob", integration.name
      assert integration.status.active?
    end

    test "create persists an error-status integration when verification fails" do
      fake = Fakes::FakeGitlabService.new(
        verify_error: Gitlab::TokenService::AuthenticationError.new("GitLab token verification failed: 401")
      )
      stub_token_service(fake)

      integration = nil
      assert_difference -> { Integration.count }, 1 do
        integration = Gitlab::IntegrationService
          .new(company: @company, connected_by: @user)
          .create(personal_access_token: "glpat-bad")
      end

      assert integration.persisted?, integration.errors.full_messages.to_sentence
      assert fake.called?(:verify_token)

      integration.reload
      assert integration.status.error?
      assert_equal "GitLab (unverified)", integration.name
      assert_equal "GitLab token verification failed: 401", integration.settings["error"]
    end
  end
end
