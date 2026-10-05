# frozen_string_literal: true

require "test_helper"

class WorkflowRunResourceTest < ActiveSupport::TestCase
  setup do
    @workflow = create(:workflow, :with_project_scope)
    @project = @workflow.scope
    @run = create(:workflow_run, workflow: @workflow, project: @project)
    @owner = @run.user
    @session = create(:terminal_session, :agent_session, user: @owner, project: @project, state: "ready")
    create(:step_run, workflow_run: @run, step: create(:step, workflow: @workflow), terminal_session: @session)
  end

  test "a ready step hands its owner the writable terminal socket and a colleague the read-only one" do
    @owner.update!(share_active_sessions: true)
    colleague = create(:user, :employee, company: @owner.companies.first)

    own = WorkflowRunResource.new(@run.reload, params: { viewer: @owner }).to_h["stepRuns"].first
    shared = WorkflowRunResource.new(@run.reload, params: { viewer: colleague }).to_h["stepRuns"].first

    assert own["websocketUrl"].start_with?("#{Settings.traefik.ws_base}/t/#{@session.route_token}/tty/ws")
    assert shared["websocketUrl"].start_with?("#{Settings.traefik.ws_base}/t/#{@session.route_token}/view/ws")
    assert own["uploadUrl"].start_with?("#{Settings.traefik.http_base}/t/#{@session.route_token}/upload")
    assert_nil shared["uploadUrl"]
  end

  test "a colleague gets no terminal socket for a step whose owner does not share it" do
    @owner.update!(share_active_sessions: false)
    colleague = create(:user, :employee, company: @owner.companies.first)

    step = WorkflowRunResource.new(@run.reload, params: { viewer: colleague }).to_h["stepRuns"].first

    assert_nil step["websocketUrl"]
  end

  test "a step whose container is not up yet has no terminal socket" do
    @session.update!(state: "running")

    step = WorkflowRunResource.new(@run.reload, params: { viewer: @owner }).to_h["stepRuns"].first

    assert_nil step["websocketUrl"]
  end

  test "a chat-started run names where its request came from; any other run, nothing" do
    @run.update!(shared_context: { "chat" => {
      "provider" => "teams", "conversation" => { "id" => "19:a", "name" => "Onboarding", "team" => { "name" => "Sales" } },
      "actor" => { "name" => "Olo Brockhouse" }, "url" => "https://teams.microsoft.com/l/message/19:a/1"
    } })

    assert_equal({ "provider" => "Microsoft Teams", "conversation" => "Sales / Onboarding", "sender" => "Olo Brockhouse",
                   "url" => "https://teams.microsoft.com/l/message/19:a/1" }, WorkflowRunResource.new(@run).to_h["chatOrigin"])

    @run.update!(shared_context: {})
    assert_nil WorkflowRunResource.new(@run).to_h["chatOrigin"]
  end
end
