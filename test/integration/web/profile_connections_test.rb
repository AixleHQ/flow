# frozen_string_literal: true

require "test_helper"

class Web::ProfileConnectionsTest < ActionDispatch::IntegrationTest
  setup do
    Settings.github.stubs(:client_id).returns("Iv1.client")
    Settings.github.stubs(:client_secret).returns("client-secret")
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user, name: "Alpha")
    sign_in_as(@user)
  end

  def json_patch(params)
    patch act_as_consents_profile_path, params: params.to_json,
                                        headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  test "the page lists the connection and a row per project with both switches off" do
    create(:oauth_credential, :github_user, owner: @user)

    get connections_profile_path

    assert_inertia_page "Profile/Connections"
    props = inertia.props
    assert props[:available]
    assert_equal "connected", props[:github][:status]
    assert_equal "octo-user", props[:github][:login]
    assert_equal [ { projectId: @project.id, inOwnTasks: false, inOthersTasks: false, projectName: "Alpha" } ],
                 props[:consents].map { |row| row.symbolize_keys.slice(:projectId, :inOwnTasks, :inOthersTasks, :projectName) }
    assert_not_includes props[:github].to_json, "at-"
  end

  test "without a connection the page offers Connect, and says when the App is not configured" do
    Settings.github.stubs(:client_secret).returns("")

    get connections_profile_path

    assert_nil inertia.props[:github]
    assert_not inertia.props[:available]
  end

  test "a revoked connection reads as needing a reconnect" do
    create(:oauth_credential, :github_user, owner: @user, status: :revoked)

    get connections_profile_path

    assert_equal "needs_reconnect", inertia.props[:github][:status]
  end

  test "a consent update stores the switch and leaves the other alone" do
    json_patch(project_id: @project.id, provider: "github", in_own_tasks: true)

    assert_response :success
    consent = ActAsConsent.find_by!(user: @user, project: @project, provider: "github")
    assert consent.in_own_tasks
    assert_not consent.in_others_tasks

    json_patch(project_id: @project.id, provider: "github", in_others_tasks: true)

    assert consent.reload.in_own_tasks
    assert consent.in_others_tasks
  end

  test "a consent update for a project outside the company answers 404" do
    other_company = create(:company)
    foreign = create(:project, company: other_company, owner: create(:user, :admin, company: other_company))

    json_patch(project_id: foreign.id, provider: "github", in_own_tasks: true)

    assert_response :not_found
    assert_equal 0, ActAsConsent.count
  end

  test "a consent update for an unknown provider answers 404" do
    json_patch(project_id: @project.id, provider: "gitlab", in_own_tasks: true)

    assert_response :not_found
  end

  test "disconnect revokes the grant, removes the credential and the consents, and keeps issuances" do
    credential = create(:oauth_credential, :github_user, owner: @user)
    create(:act_as_consent, :own, user: @user, project: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    issuance = UserTokenIssuance.create!(terminal_session: session, company: @company, project: @project,
                                         acting_for_user: @user, tool_name: "github_user_token", provider: "github",
                                         oauth_credential: credential, token: "ghu_x", target_login: "acme")
    fake = FakeGithub::UserTokenService.new
    Github::UserTokenService.stubs(:new).returns(fake)

    delete disconnect_profile_path("github")

    assert_redirected_to connections_profile_path
    assert fake.called?(:revoke_grant)
    assert_nil OauthCredential.find_by(id: credential.id)
    assert_equal 0, ActAsConsent.where(user: @user).count
    assert_nil issuance.reload.oauth_credential_id
  end

  test "disconnect still removes the connection when GitHub is unreachable" do
    credential = create(:oauth_credential, :github_user, owner: @user)
    Github::UserTokenService.stubs(:new).returns(
      FakeGithub::UserTokenService.new(revoke_error: Github::UserTokenService::Unavailable.new("down"))
    )

    delete disconnect_profile_path("github")

    assert_nil OauthCredential.find_by(id: credential.id)
  end

  test "disconnect never touches another user's connection" do
    other = create(:user, :employee, company: @company)
    theirs = create(:oauth_credential, :github_user, owner: other)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)

    delete disconnect_profile_path("github")

    assert OauthCredential.exists?(theirs.id)
  end
end
