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
    def stub_token_service(installation: nil, identity: nil, verify_error: nil)
      options = { installation: installation, identity: identity, verify_error: verify_error }.compact
      fake = FakeGithub::TokenService.new(**options)
      Github::TokenService.stubs(:new).returns(fake)
      fake
    end

    test "happy path: persists an active company-wide integration from the verified installation" do
      fake = stub_token_service

      integration = nil
      assert_difference("Integration.count", 1) do
        integration = Github::IntegrationService.new(company: @company, connected_by: @user)
          .create(installation_id: "12345", via_setup: true)
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
        .create(installation_id: "67890", via_setup: true)

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
      ).create(installation_id: "12345", via_setup: true)

      assert integration.active?
      assert_equal project.id, integration.project_id
    end

    # ----- PAT mode -----

    test "create_with_pat persists an active connection with no installation" do
      fake = stub_token_service
      project = create(:project, company: @company, owner: @user)

      integration = nil
      assert_difference("Integration.count", 1) do
        integration = Github::IntegrationService.new(
          company: @company, connected_by: @user, project: project
        ).create_with_pat(personal_access_token: "ghp_developer_token")
      end

      assert integration.persisted?
      assert integration.active?
      assert integration.github_pat?
      assert_equal "octodev", integration.name
      assert_equal "pat", integration.reload.github_auth_mode
      assert_equal "octodev", integration.github_account_login
      assert_equal %w[repo], integration.settings["token_scopes"]
      assert_equal "ghp_developer_token", integration.github_personal_access_token
      assert_nil integration.installation_id
      assert fake.called?(:verify_token)
    end

    test "create_with_pat records no token_scopes for a fine-grained token" do
      stub_token_service(identity: { id: 7, account_login: "octodev", account_type: "User", scopes: nil })

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create_with_pat(personal_access_token: "github_pat_x")

      assert integration.active?
      assert_nil integration.settings["token_scopes"]
    end

    # The whole point of the mode: it works where the deployment has no GitHub
    # App at all, so nothing may consult Settings.github.
    test "create_with_pat works with no GitHub App configured" do
      Settings.github.stubs(:app_id).returns(nil)
      Settings.github.stubs(:app_slug).returns(nil)
      stub_request(:get, "https://api.github.com/user")
        .to_return(status: 200, headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "repo" },
                   body: { id: 4_242, login: "octodev", type: "User" }.to_json)

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create_with_pat(personal_access_token: "ghp_developer_token")

      assert integration.active?
      assert_equal "octodev", integration.name
    end

    test "create_with_pat does not persist a connection for a token GitHub rejects" do
      stub_token_service(verify_error: Github::TokenService::AuthenticationError.new("GitHub rejected this token"))

      integration = nil
      assert_no_difference("Integration.count") do
        integration = Github::IntegrationService.new(company: @company, connected_by: @user)
          .create_with_pat(personal_access_token: "ghp_revoked")
      end

      refute_predicate integration, :persisted?
      refute_predicate integration, :active?
      assert_equal "GitHub rejected this token", integration.settings["error"]
    end

    # Re-pasting is how a PAT connection is repaired, so it must replace the
    # token on the row a project already has rather than stack a second one.
    test "create_with_pat replaces the token on an existing PAT connection" do
      stub_token_service
      project = create(:project, company: @company, owner: @user)
      service = Github::IntegrationService.new(company: @company, connected_by: @user, project: project)

      first = service.create_with_pat(personal_access_token: "ghp_old")

      second = nil
      assert_no_difference("Integration.count") do
        second = service.create_with_pat(personal_access_token: "ghp_new")
      end

      assert_equal first.id, second.id
      assert_equal "ghp_new", second.reload.github_personal_access_token
    end

    # A typo on re-connect must not take a working connection down: the row is
    # left alone, token and all.
    test "a rejected re-connect leaves the stored token intact" do
      stub_token_service
      project = create(:project, company: @company, owner: @user)
      service = Github::IntegrationService.new(company: @company, connected_by: @user, project: project)
      existing = service.create_with_pat(personal_access_token: "ghp_working")

      stub_token_service(verify_error: Github::TokenService::AuthenticationError.new("Bad credentials"))
      rejected = service.create_with_pat(personal_access_token: "ghp_typo")

      assert existing.reload.active?
      assert_equal "ghp_working", existing.github_personal_access_token
      # The attempt reports as failed even though the row it targeted is still
      # active from last time — otherwise a rejected re-paste reads as success.
      refute_predicate rejected, :active?
      assert_equal "Bad credentials", rejected.settings["error"]
    end

    # An App installation is a different kind of connection and keeps its own
    # row — a project can hold both.
    test "create_with_pat leaves an App installation in the same project alone" do
      stub_token_service
      project = create(:project, company: @company, owner: @user)
      service = Github::IntegrationService.new(company: @company, connected_by: @user, project: project)
      app_integration = service.create(installation_id: "12345", via_setup: true)

      assert_difference("Integration.count", 1) do
        service.create_with_pat(personal_access_token: "ghp_developer_token")
      end

      assert app_integration.reload.github_app?
    end

    test "coerces a non-string installation_id to a string in credentials" do
      stub_token_service

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: 12_345, via_setup: true)

      assert integration.persisted?
      assert_equal "12345", integration.credentials_data["installation_id"]
    end

    # ----- Installation claims -----
    #
    # Every customer installs the same App and its JWT can read every
    # installation, so "it exists" says nothing about whose it is.

    test "link to project refuses an installation the company does not hold" do
      stub_token_service
      project = create(:project, company: @company, owner: @user)

      integration = nil
      assert_no_difference("Integration.count") do
        integration = Github::IntegrationService.new(company: @company, connected_by: @user, project: project)
          .create(installation_id: "55555")
      end

      assert_not integration.persisted?
      assert_match(/not connected to this workspace/, integration.settings["error"])
    end

    test "link to project reuses an installation the company already holds" do
      stub_token_service
      Github::IntegrationService.new(company: @company, connected_by: @user).create(installation_id: "55555", via_setup: true)
      project = create(:project, company: @company, owner: @user)

      integration = Github::IntegrationService.new(company: @company, connected_by: @user, project: project)
        .create(installation_id: "55555")

      assert integration.persisted?
      assert integration.active?
      assert_equal project.id, integration.project_id
    end

    test "an installation another company has connected cannot be connected again" do
      stub_token_service
      other_company = create(:company)
      Github::IntegrationService.new(company: other_company, connected_by: create(:user, :admin, company: other_company))
        .create(installation_id: "77777", via_setup: true)

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: "77777", via_setup: true)

      assert_not integration.persisted?
      assert_includes integration.errors.full_messages, "This GitHub installation is already connected to another workspace"
    end

    test "with the installer confirmed by GitHub, one installation can serve two companies" do
      stub_token_service
      other_company = create(:company)
      Github::IntegrationService.new(company: other_company, connected_by: create(:user, :admin, company: other_company))
        .create(installation_id: "77777", via_setup: true)
      Github::InstallationOwnership.stubs(:enforced?).returns(true)
      ownership = mock("ownership")
      ownership.stubs(:includes?).with("77777").returns(true)
      Github::InstallationOwnership.stubs(:new).with(code: "oauth-code").returns(ownership)

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: "77777", via_setup: true, oauth_code: "oauth-code")

      assert integration.persisted?
      assert integration.active?
      assert_equal [ other_company.id, @company.id ].sort,
                   Integration.where(provider: :github, github_installation_id: 77_777, status: "active").pluck(:company_id).sort
    end

    test "with the App's OAuth client configured, a new installation needs the installer's confirmation" do
      stub_token_service
      Github::InstallationOwnership.stubs(:enforced?).returns(true)
      ownership = mock("ownership")
      ownership.stubs(:includes?).with("88888").returns(false)
      Github::InstallationOwnership.stubs(:new).with(code: nil).returns(ownership)

      integration = Github::IntegrationService.new(company: @company, connected_by: @user)
        .create(installation_id: "88888", via_setup: true)

      assert_not integration.persisted?
      assert_match(/Could not confirm/, integration.settings["error"])
    end
  end
end
