# frozen_string_literal: true

require "test_helper"

# What this resource says about a session that is not up yet is the entire
# explanation a person gets for the wait, so a wrong answer here is a wrong
# answer on every screen.
class TerminalSessionResourceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    # Only project sessions are queued, and the launch phases this resource
    # reports are the queue's, so every fixture here is project-bound.
    @project = create(:project, owner: @user, company: @user.companies.first)
    with_scope_defaults(project: 1)
  end

  def payload(session) = TerminalSessionResource.new(session.reload).to_h

  test "a session nobody has a slot for is reported as waiting for one" do
    holder = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(holder)
    SessionAdmissionService.drain!
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!

    assert_equal "queued_for_slot", payload(session)["launchPhase"]
  end

  # The bug this exists for: a session stays in `queued` from the moment the row
  # is written until the container workflow's first activity calls `start!` —
  # right through dispatch. Screens read that state as "waiting for a slot", so
  # an authentication session that was granted its slot in one second spent its
  # whole launch telling the user to wait for capacity, with the user's own
  # limit nowhere near full.
  test "a session whose slot is already granted is not reported as waiting for capacity" do
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!

    assert_equal "queued", session.reload.state, "the state alone cannot answer this"
    assert_equal "starting", payload(session)["launchPhase"]
  end

  test "cluster capacity is reported as itself, not as a queue position" do
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    session.session_admission.update!(wait_reason: "cluster_capacity")

    assert_equal "cluster_capacity", payload(session)["launchPhase"]
  end

  test "a launch that is running reports neither a wait nor an error" do
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    session.session_admission.update!(launch_state: "acknowledged", wait_reason: nil)

    assert_equal "running", payload(session)["launchPhase"]
    assert_nil payload(session)["launchError"]
  end

  # A refused preflight must not leave the session sitting in `queued` with
  # nothing but the queue's own explanation on screen.
  test "the launch's own failure is carried to the screen" do
    session = create(:terminal_session, user: @user, project: @project)
    SessionAdmissionService.enqueue!(session)
    session.session_admission.update!(last_error: "GitHub token expired; reconnect the integration")

    assert_equal "GitHub token expired; reconnect the integration", payload(session)["launchError"]
  end

  test "a session with no admission at all says nothing about slots" do
    session = create(:terminal_session, user: @user, project: @project)

    assert_nil payload(session)["launchPhase"]
    assert_nil payload(session)["launchError"]
  end

  # == shared sessions ==

  test "someone the session is shared with gets the read-only terminal, no IDE and no IDE token" do
    colleague = create(:user, :employee, company: @user.companies.first)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, state: "ready",
                                                        metadata: { "vscode_token" => "tkn-secret", "note" => "x" })

    shared = TerminalSessionResource.new(session.reload, params: { viewer: colleague }).to_h
    own = TerminalSessionResource.new(session, params: { viewer: @user }).to_h

    assert_match %r{/t/#{session.route_token}/view/ws\z}, shared["websocketUrl"]
    assert_nil shared["ideUrl"]
    assert_not shared.to_json.include?("tkn-secret")
    assert_match %r{/t/#{session.route_token}/tty/ws\z}, own["websocketUrl"]
    assert_includes own["ideUrl"], "tkn-secret"
    # Only the owner may paste an image into the container.
    assert_nil shared["uploadUrl"]
    assert_match %r{/t/#{session.route_token}/upload\z}, own["uploadUrl"]
  end

  test "served from a host of their own, container URLs carry the viewer's ticket" do
    Settings.stubs(:domain).returns("flow.example.com")
    Settings.traefik.stubs(:http_base).returns("https://t.flow.example.com")
    Settings.traefik.stubs(:ws_base).returns("wss://t.flow.example.com")
    session = create(:terminal_session, :agent_session, user: @user, project: @project, state: "ready")

    url = TerminalSessionResource.new(session, params: { viewer: @user }).to_h["websocketUrl"]

    assert url.start_with?("wss://t.flow.example.com/t/#{session.route_token}/tty/ws?#{ContainerTicket::PARAM}=")
    ticket = Rack::Utils.parse_query(URI.parse(url).query)[ContainerTicket::PARAM]
    assert_equal @user, ContainerTicket.user_for(ticket, session: session)
  end

  test "without a viewer the payload is a stranger's: redacted, read-only and without a ticket" do
    Settings.stubs(:domain).returns("flow.example.com")
    Settings.traefik.stubs(:http_base).returns("https://t.flow.example.com")
    Settings.traefik.stubs(:ws_base).returns("wss://t.flow.example.com")
    session = create(:terminal_session, :agent_session, user: @user, project: @project, state: "ready",
                                                        initial_prompt: "private plan",
                                                        metadata: { "vscode_token" => "tkn-secret" })

    anonymous = payload(session)

    assert_nil anonymous["initialPrompt"]
    assert_nil anonymous["metadata"]
    assert_equal false, anonymous["ownedByViewer"] # rubocop:disable Minitest/RefuteFalse
    assert_equal "wss://t.flow.example.com/t/#{session.route_token}/view/ws", anonymous["websocketUrl"]
    assert_nil anonymous["uploadUrl"]
    assert_nil anonymous["ideUrl"]
  end

  # A failed clone is left out of the agent's context; this is how the person
  # watching the session learns which repository is missing, and why.
  test "repositories that did not clone are reported to those who may see the session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, state: "ready",
                                                        metadata: { "failed_repos" => [
                                                          { "id" => 3, "full_name" => "acme/api", "error" => "Integration not active" }
                                                        ] })

    own = TerminalSessionResource.new(session, params: { viewer: @user }).to_h

    assert_equal [ { "id" => 3, "fullName" => "acme/api", "error" => "Integration not active" } ], own["failedRepositories"]
    assert_equal [], payload(session)["failedRepositories"]
  end

  test "config files keep their paths through every camelizing pass" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
                                                        session_config: { "config_files" => { "/workspace/.aixle/references/guide.md" => "# Guide" } })

    props = DeepKeyCamelizer.call(TerminalSessionResource.new(session, params: { viewer: @user }).to_h)

    assert_equal [ { "path" => "/workspace/.aixle/references/guide.md", "content" => "# Guide" } ],
                 props.dig("sessionConfig", "configFiles")
  end
end
