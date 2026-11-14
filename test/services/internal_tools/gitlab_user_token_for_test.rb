# frozen_string_literal: true

require "test_helper"

class InternalTools::GitlabUserTokenForTest < ActiveSupport::TestCase
  setup do
    stub_container_runtime
    Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
    Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")

    @company = create(:company)
    @owner = create(:user, :admin, company: @company, name: "Owner")
    @colleague = create(:user, :employee, company: @company, name: "Colleague")
    @project = create(:project, company: @company, owner: @owner)
    create(:project_collaborator, project: @project, user: @colleague)
    @session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    integration = create(:integration, :gitlab, :active, company: @company)
    @session.repositories << create(:repository, scope: @project, integration: integration, full_name: "group/app")
    @credential = create(:oauth_credential, :gitlab_user, owner: @colleague)
    Gitlab::UserTokenService.stubs(:new).returns(FakeGitlab::UserTokenService.new)
  end

  teardown { cleanup_runtime_overrides }

  def run_tool(user_id)
    InternalTools::GitlabUserTokenFor.new(params: { user_id: user_id }, session: @session).execute
  end

  def consent!(user, **flags)
    create(:act_as_consent, user: user, project: @project, provider: "gitlab", **flags)
  end

  test "another member needs the switch for tasks that aren't theirs" do
    consent!(@colleague, in_own_tasks: true)

    result = run_tool(@colleague.id)

    assert_equal 1, result[:exit_code]
    assert_match(/GitLab account to be used in tasks that aren't theirs/, result[:stderr])
  end

  test "returns the named member's token and identity with the others-tasks switch on" do
    consent!(@colleague, in_others_tasks: true)

    payload = JSON.parse(run_tool(@colleague.id)[:stdout])

    assert_equal @colleague.id, payload["user"]["id"]
    assert_equal "lab-user", payload["identity"]["login"]
    assert_equal @credential.access_token, payload["tokens"].sole["token"]
    assert_equal @colleague, UserTokenIssuance.sole.acting_for_user
    assert_equal @owner, UserTokenIssuance.sole.session_user
  end

  test "naming the session's own user checks the own-tasks switch" do
    create(:oauth_credential, :gitlab_user, owner: @owner, oauth_client: @credential.oauth_client)
    consent!(@owner, in_others_tasks: true)

    assert_match(/their own tasks/, run_tool(@owner.id)[:stderr])

    ActAsConsent.find_by!(user: @owner, provider: "gitlab").update!(in_own_tasks: true)

    assert_equal 0, run_tool(@owner.id)[:exit_code]
  end

  test "errors for an id that is not a member of this company" do
    stranger = create(:user, :employee, company: create(:company))

    assert_match(/No member with id #{stranger.id} in this company/, run_tool(stranger.id)[:stderr])
  end

  test "errors without a session user" do
    @session.stubs(:user).returns(nil)

    assert_match(/no user/, run_tool(@colleague.id)[:stderr])
  end

  test "errors when the named member has not connected an account" do
    @credential.destroy!
    consent!(@colleague, in_others_tasks: true)

    assert_match(/Colleague has not connected a GitLab account/, run_tool(@colleague.id)[:stderr])
  end
end
