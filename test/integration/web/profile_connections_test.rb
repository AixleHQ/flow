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

  def json_patch(project_id, provider: "github", **body)
    patch profile_connection_act_as_consent_path(provider, project_id), params: body.to_json,
                                                                         headers: { "Content-Type" => "application/json",
                                                                                    "Accept" => "application/json" }
  end

  test "the page lists the connection and a row per project with both switches off" do
    create(:oauth_credential, :github_user, owner: @user)

    get profile_connections_path

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

    get profile_connections_path

    assert_nil inertia.props[:github]
    assert_not inertia.props[:available]
  end

  test "a revoked connection reads as needing a reconnect" do
    create(:oauth_credential, :github_user, owner: @user, status: :revoked)

    get profile_connections_path

    assert_equal "needs_reconnect", inertia.props[:github][:status]
  end

  test "a consent update stores the switch and leaves the other alone" do
    json_patch(@project.id, in_own_tasks: true)

    assert_response :success
    consent = ActAsConsent.find_by!(user: @user, project: @project, provider: "github")
    assert consent.in_own_tasks
    assert_not consent.in_others_tasks

    json_patch(@project.id, in_others_tasks: true)

    assert consent.reload.in_own_tasks
    assert consent.in_others_tasks
  end

  test "two overlapping first-time updates for one project both save" do
    winner = ActAsConsent.create!(user: @user, project: @project, company: @project.company, provider: "github",
                                  in_others_tasks: true)
    # This request looked before the other one committed its first-time row.
    ActAsConsent.stubs(:find_by).returns(nil).then.returns(winner)

    json_patch(@project.id, in_own_tasks: true)

    assert_response :success
    consent = ActAsConsent.find_by!(user: @user, project: @project, provider: "github")
    assert consent.in_own_tasks
    assert consent.in_others_tasks
    assert_equal 1, ActAsConsent.where(user: @user, project: @project, provider: "github").count
  end

  test "a consent update for a project outside the company answers 404" do
    other_company = create(:company)
    foreign = create(:project, company: other_company, owner: create(:user, :admin, company: other_company))

    json_patch(foreign.id, in_own_tasks: true)

    assert_response :not_found
    assert_equal 0, ActAsConsent.count
  end

  test "a switch that is not a JSON boolean is refused with 422 and changes nothing" do
    [ "true", 1, "yes", nil, [ true ] ].each do |value|
      json_patch(@project.id, in_own_tasks: value)

      assert_response :unprocessable_entity, "#{value.inspect} should be refused"
    end
    json_patch(@project.id, in_own_tasks: true, in_others_tasks: "false")

    assert_response :unprocessable_entity
    assert_equal 0, ActAsConsent.count
  end

  test "a consent update can turn a switch off again" do
    create(:act_as_consent, :own, user: @user, project: @project)

    json_patch(@project.id, in_own_tasks: false)

    assert_response :success
    assert_not ActAsConsent.find_by!(user: @user, project: @project).in_own_tasks
  end

  test "a signed-out visitor is sent to login by every connections route" do
    reset!

    get profile_connections_path
    assert_redirected_to login_path
    delete profile_connection_path("github")
    assert_redirected_to login_path
    json_patch(@project.id, in_own_tasks: true)
    assert_redirected_to login_path
    assert_equal 0, ActAsConsent.count
  end

  test "disconnect of an unknown provider answers 404" do
    delete profile_connection_path("gitlab")

    assert_response :not_found
  end

  test "a consent update for an unknown provider answers 404" do
    json_patch(@project.id, provider: "gitlab", in_own_tasks: true)

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

    delete profile_connection_path("github")

    assert_redirected_to profile_connections_path
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

    delete profile_connection_path("github")

    assert_nil OauthCredential.find_by(id: credential.id)
  end

  test "disconnect never touches another user's connection" do
    other = create(:user, :employee, company: @company)
    theirs = create(:oauth_credential, :github_user, owner: other)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)

    delete profile_connection_path("github")

    assert OauthCredential.exists?(theirs.id)
  end
end
