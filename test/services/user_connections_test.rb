# frozen_string_literal: true

require "test_helper"

class UserConnectionsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, :onboarding_completed, company: @company)
    @alpha = create(:project, company: @company, owner: @user, name: "Alpha")
    @beta = create(:project, company: @company, owner: @user, name: "Beta")
  end

  test "available? follows the App's client credentials" do
    Settings.github.stubs(:client_id).returns("Iv1.client")
    Settings.github.stubs(:client_secret).returns("")

    assert_not UserConnections.available?(provider: "github")

    Settings.github.stubs(:client_secret).returns("secret")

    assert UserConnections.available?(provider: "github")
  end

  test "connection returns the latest credential, a revoked one included" do
    revoked = create(:oauth_credential, :github_user, owner: @user, status: :revoked)

    assert_equal revoked, UserConnections.connection(user: @user, provider: "github")
  end

  test "consents lists a row per reachable project, both switches off without a stored row" do
    create(:act_as_consent, :own, user: @user, project: @alpha)

    rows = UserConnections.consents(user: @user, company: @company, provider: "github")

    assert_equal %w[Alpha Beta], rows.map { |row| row.project.name }
    assert_equal [ true, false ], rows.map(&:in_own_tasks)
    assert_predicate rows.last, :new_record?
  end

  test "consents is empty without a company" do
    assert_empty UserConnections.consents(user: @user, company: nil, provider: "github")
  end

  test "update_consent! creates the row and sets only the given switch" do
    consent = UserConnections.update_consent!(user: @user, company: @company, provider: "github",
                                              project_id: @alpha.id, in_own_tasks: true)

    assert_predicate consent, :persisted?
    assert consent.in_own_tasks
    assert_not consent.in_others_tasks

    UserConnections.update_consent!(user: @user, company: @company, provider: "github",
                                    project_id: @alpha.id, in_others_tasks: true)

    assert consent.reload.in_own_tasks
    assert consent.in_others_tasks
  end

  test "update_consent! refuses a project outside the company or out of reach" do
    other_company = create(:company)
    foreign = create(:project, company: other_company,
                               owner: create(:user, :employee, :onboarding_completed, company: other_company))

    [ foreign.id, 0 ].each do |project_id|
      assert_raises(UserConnections::ProjectNotFound) do
        UserConnections.update_consent!(user: @user, company: @company, provider: "github", project_id: project_id)
      end
    end
    assert_raises(UserConnections::ProjectNotFound) do
      UserConnections.update_consent!(user: @user, company: nil, provider: "github", project_id: @alpha.id)
    end
    assert_equal 0, ActAsConsent.count
  end

  test "every operation refuses an unknown provider" do
    assert_raises(UserConnections::UnknownProvider) { UserConnections.connection(user: @user, provider: "bitbucket") }
    assert_raises(UserConnections::UnknownProvider) { UserConnections.disconnect!(user: @user, provider: "bitbucket") }
    assert_raises(UserConnections::UnknownProvider) do
      UserConnections.update_consent!(user: @user, company: @company, provider: "bitbucket", project_id: @alpha.id)
    end
  end

  test "disconnect! removes the connection and the consents" do
    credential = create(:oauth_credential, :github_user, owner: @user)
    create(:act_as_consent, :own, user: @user, project: @alpha)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)

    UserConnections.disconnect!(user: @user, provider: "github")

    assert_nil OauthCredential.find_by(id: credential.id)
    assert_equal 0, ActAsConsent.where(user: @user).count
  end

  test "connection finds a GitLab connection on the current host, apart from GitHub's" do
    github = create(:oauth_credential, :github_user, owner: @user)
    gitlab = create(:oauth_credential, :gitlab_user, owner: @user)

    assert_equal github, UserConnections.connection(user: @user, provider: "github")
    assert_equal gitlab, UserConnections.connection(user: @user, provider: "gitlab")
  end

  test "available? for gitlab follows the OAuth app's settings" do
    Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
    Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")

    assert UserConnections.available?(provider: "gitlab")

    Settings.gitlab.stubs(:oauth_client_secret).returns("")

    assert_not UserConnections.available?(provider: "gitlab")
  end

  test "consents and update_consent! work per provider" do
    UserConnections.update_consent!(user: @user, company: @company, provider: "gitlab", project_id: @alpha.id,
                                    in_own_tasks: true)

    gitlab_rows = UserConnections.consents(user: @user, company: @company, provider: "gitlab")
    github_rows = UserConnections.consents(user: @user, company: @company, provider: "github")

    assert gitlab_rows.find { |row| row.project_id == @alpha.id }.in_own_tasks
    assert_not github_rows.any?(&:in_own_tasks)
  end

  test "disconnect! for gitlab leaves GitHub's connection and consents alone" do
    gitlab = create(:oauth_credential, :gitlab_user, owner: @user)
    github = create(:oauth_credential, :github_user, owner: @user)
    create(:act_as_consent, :own, user: @user, project: @alpha, provider: "gitlab")
    create(:act_as_consent, :own, user: @user, project: @alpha, provider: "github")
    Gitlab::UserTokenService.stubs(:new).returns(FakeGitlab::UserTokenService.new)

    UserConnections.disconnect!(user: @user, provider: "gitlab")

    assert_nil OauthCredential.find_by(id: gitlab.id)
    assert OauthCredential.exists?(github.id)
    assert_equal [ "github" ], ActAsConsent.where(user: @user).pluck(:provider)
  end

  test "disconnect! for gitlab revokes only the current host's grant and deletes an old host's without a request" do
    current = create(:oauth_credential, :gitlab_user, owner: @user)
    old_host = create(:oauth_client, :gitlab, issuer: "https://old.gitlab.example.com")
    old = create(:oauth_credential, :gitlab_user, owner: @user, oauth_client: old_host)
    fake = FakeGitlab::UserTokenService.new
    Gitlab::UserTokenService.stubs(:new).returns(fake)

    UserConnections.disconnect!(user: @user, provider: "gitlab")

    assert_equal 1, fake.calls_to(:revoke).size
    assert_nil OauthCredential.find_by(id: current.id)
    assert_nil OauthCredential.find_by(id: old.id)
  end

  test "available_providers, connections_of, consents_of and label answer for every provider" do
    github = create(:oauth_credential, :github_user, owner: @user)

    assert_equal %w[github gitlab], UserConnections.available_providers.keys
    assert_equal({ "github" => github, "gitlab" => nil }, UserConnections.connections_of(user: @user))
    assert_equal %w[github gitlab], UserConnections.consents_of(user: @user, company: @company).keys
    assert_equal "GitLab", UserConnections.label(provider: "gitlab")
    assert_raises(UserConnections::UnknownProvider) { UserConnections.label(provider: "bitbucket") }
  end
end
