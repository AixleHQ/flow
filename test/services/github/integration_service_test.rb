# frozen_string_literal: true

require "test_helper"

module Github
  class IntegrationServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
    end

    # Fake at the app-owned GitHub boundary (testing doctrine R3): stub the real
    # constant and hand back FakeGithub::TokenService so no Octokit call is made.
    def stub_token_service(installation: nil)
      fake =
        if installation
          FakeGithub::TokenService.new(installation: installation)
        else
          FakeGithub::TokenService.new
        end
      Github::TokenService.stubs(:new).returns(fake)
      fake
    end

    test "happy path: persists an active company-wide integration from the verified installation" do
      fake = stub_token_service

      integration = nil
      assert_difference("Integration.count", 1) do
        integration = Github::IntegrationService.new(company: @company, connected_by: @user)
          .create(installation_id: "12345")
      end

      assert integration.persisted?
      assert integration.valid?, integration.errors.full_messages.to_sentence
      assert_equal "active", integration.status.to_s
      assert_equal "github", integration.provider.to_s
      assert_equal "acme-corp", integration.name
      assert_equal @company.id, integration.company_id
      assert_equal @user.id, integration.connected_by_id
      assert_nil integration.project_id
      assert_equal "12345", integration.credentials_data["installation_id"]
      assert_equal "Organization", integration.settings["account_type"]
      assert_equal "Organization", integration.settings["target_type"]
      assert fake.called?(:verify_installation)
    end

    test "reflects the verified installation account info in name and settings" do
      stub_token_service(installation: {
        id: 999,
        account_login: "octocat",
        account_type: "User",
        target_type: "User",
        permissions: { contents: "read" }
      })

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: "67890")

      assert integration.active?
      assert_equal "octocat", integration.name
      assert_equal "User", integration.settings["account_type"]
      assert_equal "User", integration.settings["target_type"]
      # Recorded separately from the display name: Repository checks every
      # attached repo's owner against it, because a clone token is scoped by
      # repo NAME within this account.
      assert_equal "octocat", integration.reload.github_account_login
    end

    test "scoping: project-scoped integration is persisted with the project" do
      stub_token_service
      project = create(:project, company: @company, owner: @user)

      integration = Github::IntegrationService.new(
        company: @company, connected_by: @user, project: project
      ).create(installation_id: "12345")

      assert integration.active?
      assert_equal project.id, integration.project_id
    end

    test "coerces a non-string installation_id to a string in credentials" do
      stub_token_service

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: 12_345)

      assert integration.persisted?
      assert_equal "12345", integration.credentials_data["installation_id"]
    end
  end
end
