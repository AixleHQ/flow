# frozen_string_literal: true

require "test_helper"

class InternalTools::GithubUserTokenForTest < ActiveSupport::TestCase
  setup do
    stub_container_runtime
    Settings.github.stubs(:client_id).returns("Iv1.client")
    Settings.github.stubs(:client_secret).returns("client-secret")

    @company = create(:company)
    @owner = create(:user, :admin, company: @company, name: "Owner")
    @colleague = create(:user, :employee, company: @company, name: "Colleague")
    @project = create(:project, company: @company, owner: @owner)
    create(:project_collaborator, project: @project, user: @colleague)
    @session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    integration = create(:integration, :github, :active, company: @company)
    @session.repositories << create(:repository, scope: @project, integration: integration, full_name: "AixleHQ/flow")
    @credential = create(:oauth_credential, :github_user, owner: @colleague)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new)
  end

  teardown { cleanup_runtime_overrides }

  def run_tool(user_id)
    InternalTools::GithubUserTokenFor.new(params: { user_id: user_id }, session: @session).execute
  end

  test "another member needs the switch for tasks that aren't theirs" do
    create(:act_as_consent, :own, user: @colleague, project: @project)

    result = run_tool(@colleague.id)

    assert_equal 1, result[:exit_code]
    assert_match(/tasks that aren't theirs/, result[:stderr])
  end

  test "returns the named member's token and identity with the others-tasks switch on" do
    create(:act_as_consent, :others, user: @colleague, project: @project)

    payload = JSON.parse(run_tool(@colleague.id)[:stdout])

    assert_equal @colleague.id, payload["user"]["id"]
    assert_equal "octo-user", payload["identity"]["login"]
    assert_equal @colleague, UserTokenIssuance.sole.acting_for_user
    assert_equal @owner, UserTokenIssuance.sole.session_user
  end

  test "naming the session's own user checks the own-tasks switch" do
    create(:oauth_credential, :github_user, owner: @owner, oauth_client: @credential.oauth_client)
    create(:act_as_consent, :others, user: @owner, project: @project)

    assert_match(/their own tasks/, run_tool(@owner.id)[:stderr])

    ActAsConsent.find_by!(user: @owner).update!(in_own_tasks: true)

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
    create(:act_as_consent, :others, user: @colleague, project: @project)

    assert_match(/Colleague has not connected a GitHub account/, run_tool(@colleague.id)[:stderr])
  end
end
