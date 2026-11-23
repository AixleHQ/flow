# frozen_string_literal: true

require "test_helper"

class InternalTools::BitbucketUserTokenForTest < ActiveSupport::TestCase
  include BitbucketTestHelper

  setup do
    stub_container_runtime
    Settings.bitbucket.oauth.stubs(:client_id).returns("bb-cid")
    Settings.bitbucket.oauth.stubs(:client_secret).returns("bb-secret")

    @company = create(:company)
    @owner = create(:user, :admin, company: @company, name: "Owner")
    @colleague = create(:user, :employee, company: @company, name: "Colleague")
    @project = create(:project, company: @company, owner: @owner)
    create(:project_collaborator, project: @project, user: @colleague)
    @session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    integration = create(:integration, :bitbucket, :active, company: @company, project: @project)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: integration, full_name: "acme/api")
    @credential = create(:oauth_credential, :bitbucket_user, owner: @colleague)
    fake = stub_bitbucket!
    fake.user = { uuid: "{6c1f0a4e-0000-4000-8000-0000000000b1}", account_id: "712020:abc", display_name: "Bee Bucket",
                  nickname: "bb-user", avatar_url: nil }
    fake.permissions = { "acme/api" => "write" }
  end

  teardown { cleanup_runtime_overrides }

  def run_tool(user_id)
    InternalTools::BitbucketUserTokenFor.new(params: { user_id: user_id }, session: @session).execute
  end

  def consent!(user, **flags)
    create(:act_as_consent, user: user, project: @project, provider: "bitbucket", **flags)
  end

  test "another member needs the switch for tasks that aren't theirs" do
    consent!(@colleague, in_own_tasks: true)

    result = run_tool(@colleague.id)

    assert_equal 1, result[:exit_code]
    assert_match(/Bitbucket account to be used in tasks that aren't theirs/, result[:stderr])
  end

  test "returns the named member's token and identity with the others-tasks switch on" do
    consent!(@colleague, in_others_tasks: true)

    payload = JSON.parse(run_tool(@colleague.id)[:stdout])

    assert_equal @colleague.id, payload["user"]["id"]
    assert_equal "bb-user", payload["identity"]["login"]
    assert_equal @credential.access_token, payload["tokens"].sole["token"]
    assert_equal @colleague, UserTokenIssuance.sole.acting_for_user
    assert_equal @owner, UserTokenIssuance.sole.session_user
  end

  test "naming the session's own user checks the own-tasks switch" do
    create(:oauth_credential, :bitbucket_user, owner: @owner, oauth_client: @credential.oauth_client)
    consent!(@owner, in_others_tasks: true)

    assert_match(/their own tasks/, run_tool(@owner.id)[:stderr])

    ActAsConsent.find_by!(user: @owner, provider: "bitbucket").update!(in_own_tasks: true)

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

    assert_match(/Colleague has not connected a Bitbucket account/, run_tool(@colleague.id)[:stderr])
  end
end
