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
    assert props[:available][:github]
    assert_equal "connected", props[:connections][:github][:status]
    assert_equal "octo-user", props[:connections][:github][:login]
    assert_nil props[:connections][:gitlab]
    assert_equal [ { provider: "github", projectId: @project.id, inOwnTasks: false, inOthersTasks: false, projectName: "Alpha" } ],
                 props[:consents][:github].map { |row| row.symbolize_keys.slice(:provider, :projectId, :inOwnTasks, :inOthersTasks, :projectName) }
    assert_equal [ "gitlab" ], props[:consents][:gitlab].map { |row| row[:provider] }.uniq
    assert_not_includes props[:connections][:github].to_json, "at-"
  end

  test "without a connection the page offers Connect, and says when the App is not configured" do
    Settings.github.stubs(:client_secret).returns("")

    get profile_connections_path

    assert_nil inertia.props[:connections][:github]
    assert_not inertia.props[:available][:github]
  end

  test "a revoked connection reads as needing a reconnect" do
    create(:oauth_credential, :github_user, owner: @user, status: :revoked)

    get profile_connections_path

    assert_equal "needs_reconnect", inertia.props[:connections][:github][:status]
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
    delete profile_connection_path("bitbucket")

    assert_response :not_found
  end

  test "a consent update for an unknown provider answers 404" do
    json_patch(@project.id, provider: "bitbucket", in_own_tasks: true)

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

  test "the page lists a GitLab connection with its own consents, when the OAuth app is set" do
    Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
    Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")
    create(:oauth_credential, :gitlab_user, owner: @user)

    get profile_connections_path

    props = inertia.props
    assert props[:available][:gitlab]
    assert_equal "connected", props[:connections][:gitlab][:status]
    assert_equal "gitlab", props[:connections][:gitlab][:provider]
    assert_equal "lab-user", props[:connections][:gitlab][:login]
    assert_equal "Lab User", props[:connections][:gitlab][:name]
    assert_nil props[:connections][:github]
    assert_equal [ "Alpha" ], props[:consents][:gitlab].map { |row| row[:projectName] }
    assert_not_includes props[:connections][:gitlab].to_json, "at-"
  end

  test "GitLab is not offered without the OAuth app" do
    Settings.gitlab.stubs(:oauth_client_id).returns("")

    get profile_connections_path

    assert_not inertia.props[:available][:gitlab]
  end

  test "a GitLab consent update stores the switch under the gitlab provider only" do
    json_patch(@project.id, provider: "gitlab", in_others_tasks: true)

    assert_response :success
    consent = ActAsConsent.find_by!(user: @user, project: @project, provider: "gitlab")
    assert consent.in_others_tasks
    assert_equal "gitlab", JSON.parse(response.body)["provider"]
    assert_nil ActAsConsent.find_by(user: @user, project: @project, provider: "github")
  end

  test "disconnecting GitLab revokes the grant, removes the credential and its consents, and leaves GitHub alone" do
    gitlab = create(:oauth_credential, :gitlab_user, owner: @user)
    github = create(:oauth_credential, :github_user, owner: @user)
    create(:act_as_consent, :own, user: @user, project: @project, provider: "gitlab")
    create(:act_as_consent, :own, user: @user, project: @project, provider: "github")
    resolve_hosts_publicly!
    revocation = stub_request(:post, "#{Gitlab::Host.web_base}/oauth/revoke").to_return(status: 200, body: "{}")

    delete profile_connection_path("gitlab")

    assert_redirected_to profile_connections_path
    assert_equal "GitLab disconnected", flash[:notice]
    assert_requested revocation
    assert_nil OauthCredential.find_by(id: gitlab.id)
    assert OauthCredential.exists?(github.id)
    assert_equal [ "github" ], ActAsConsent.where(user: @user).pluck(:provider)
  end

  test "disconnecting GitLab still removes the connection when GitLab is unreachable" do
    credential = create(:oauth_credential, :gitlab_user, owner: @user)
    resolve_hosts_publicly!
    stub_request(:post, "#{Gitlab::Host.web_base}/oauth/revoke").to_return(status: 503, body: "down")

    delete profile_connection_path("gitlab")

    assert_nil OauthCredential.find_by(id: credential.id)
  end

  test "disconnect never touches another user's connection" do
    other = create(:user, :employee, company: @company)
    theirs = create(:oauth_credential, :github_user, owner: other)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)

    delete profile_connection_path("github")

    assert OauthCredential.exists?(theirs.id)
  end

  # --- Impersonation: an operator changes nothing about the person's GitHub connection ---

  def impersonate!
    sign_in_as(create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD))
    post impersonate_admin_user_path(@user)
  end

  test "the page stays readable while impersonating" do
    create(:oauth_credential, :github_user, owner: @user)
    impersonate!

    get profile_connections_path

    assert_inertia_page "Profile/Connections"
    assert_equal "connected", inertia.props[:connections][:github][:status]
  end

  test "disconnecting is refused while impersonating" do
    credential = create(:oauth_credential, :github_user, owner: @user)
    Github::UserTokenService.expects(:new).never
    impersonate!

    delete profile_connection_path("github")

    assert_redirected_to profile_connections_path
    assert_match(/while impersonating/, flash[:alert])
    assert OauthCredential.exists?(credential.id)
  end

  test "changing a consent is refused with 403 while impersonating" do
    create(:oauth_credential, :github_user, owner: @user)
    impersonate!

    json_patch(@project.id, in_others_tasks: true)

    assert_response :forbidden
    assert_match(/while impersonating/, response.parsed_body["error"])
    assert_equal 0, ActAsConsent.where(user: @user).count
  end
end
