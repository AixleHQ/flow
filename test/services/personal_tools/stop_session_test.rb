# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class StopSessionTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    def execute(session, actor: @user, **params)
      StopSession.new(params: { session_id: session.id, **params }, user: actor).execute
    end

    def payload(result) = JSON.parse(result[:stdout])

    test "a graceful stop finishes the session through the service" do
      session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)

      body = payload(execute(session))

      assert_equal "finish", body["stopped_with"]
      # No temporal_workflow_id, so SessionService finalizes in place instead of
      # signalling — the session lands in finished, not merely finishing.
      assert_equal "finished", session.reload.state
    end

    test "force fails the session and records the reason" do
      session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)

      body = payload(execute(session, force: true, reason: "wedged on a prompt"))

      assert_equal "fail", body["stopped_with"]
      assert_equal "failed", session.reload.state
      assert_equal "wedged on a prompt", session.error_message
    end

    test "a session that is already over is refused with its state" do
      session = create(:terminal_session, :agent_session, :collected, user: @user, project: @project)

      result = execute(session)

      assert_equal 1, result[:exit_code]
      assert_match(/already finished/, result[:stderr])
    end

    test "a member who may see the session may stop it" do
      owner = create(:user)
      create(:company_membership, user: owner, company: @company, role: :employee)
      # workflow_step sessions are team automation — visible to everyone who can
      # reach the project, regardless of the owner's sharing preferences.
      session = create(:terminal_session, :running, session_type: "workflow_step",
                       user: owner, project: @project)

      body = payload(execute(session))

      assert_equal "finished", session.reload.state
      assert_equal session.id, body["session_id"]
    end

    test "a read-only member cannot stop a session they can see" do
      viewer = create(:user)
      create(:company_membership, user: viewer, company: @company, role: :viewer)
      create(:project_collaborator, project: @project, user: viewer)
      session = create(:terminal_session, :running, session_type: "workflow_step",
                       user: @user, project: @project)

      result = execute(session, actor: viewer)

      assert_equal 1, result[:exit_code]
      assert_match(/read-only/i, result[:stderr])
      assert_equal "running", session.reload.state
    end

    test "a session in another company is not found" do
      stranger = create(:user, :with_company)
      theirs = create(:terminal_session, :agent_session, :running, user: stranger,
                      project: create(:project, owner: stranger, company: stranger.companies.first))

      assert_raises(PersonalTools::Base::NotFoundError) { execute(theirs) }
    end
  end
end
