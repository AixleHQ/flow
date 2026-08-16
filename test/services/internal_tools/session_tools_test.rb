# frozen_string_literal: true

require "test_helper"

class InternalTools::SessionToolsTest < ActiveSupport::TestCase
  setup do
    @runtime = stub_container_runtime
    @company = create(:company)
    @user    = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "supervise the run")
  end

  teardown { cleanup_runtime_overrides }

  def list(**params)
    InternalTools::SessionList.new(params: params, session: @session).execute
  end

  def log(target, **params)
    InternalTools::SessionLog.new(params: { session_id: target.id, **params }, session: @session).execute
  end

  def payload(result) = JSON.parse(result[:stdout])

  def ids(result) = payload(result)["sessions"].map { |row| row["id"] }

  # == session_list ==

  test "lists the project's active sessions and leaves finished ones out" do
    neighbour = create(:terminal_session, :running, :agent_session, user: @user, project: @project)
    finished  = create(:terminal_session, :collected, :agent_session, user: @user, project: @project)

    listed = ids(list)

    assert_includes listed, neighbour.id
    assert_includes listed, @session.id
    assert_not_includes listed, finished.id
  end

  test "state: finished lists the finished ones instead" do
    finished = create(:terminal_session, :collected, :agent_session, user: @user, project: @project)

    assert_equal [ finished.id ], ids(list(state: "finished"))
  end

  test "an unknown state is refused, naming the allowed values" do
    result = list(state: "wedged")

    assert_equal 1, result[:exit_code]
    assert_match(/active, finished, failed, all/, result[:stderr])
  end

  test "a session in another project is never listed" do
    other_project = create(:project, company: @company, owner: @user)
    theirs = create(:terminal_session, :running, :agent_session, user: @user, project: other_project)

    assert_not_includes ids(list(state: "all")), theirs.id
  end

  test "another member's session stays hidden unless they share active sessions" do
    other = create(:user)
    create(:company_membership, user: other, company: @company, role: :employee)
    theirs = create(:terminal_session, :running, :agent_session, user: other, project: @project)

    assert_not_includes ids(list), theirs.id

    other.update!(share_active_sessions: true)
    assert_includes ids(list), theirs.id
  end

  test "rows carry the workflow linkage but not the metadata blob" do
    neighbour = create(:terminal_session, :running, user: @user, project: @project,
                       session_type: "workflow_step",
                       metadata: { "workflow_run_id" => 42, "step_run_id" => 7, "step_name" => "Build",
                                   "initial_prompt" => "secret plan" })

    row = payload(list)["sessions"].find { |candidate| candidate["id"] == neighbour.id }

    assert_equal 42, row["workflow_run_id"]
    assert_equal "Build", row["step_name"]
    assert_not_includes row.keys, "metadata"
    assert_not_includes row.to_s, "secret plan"
  end

  test "the caller's own row is flagged so an agent does not mistake itself for a neighbour" do
    rows = payload(list)["sessions"]

    assert rows.find { |row| row["id"] == @session.id }["self"]
  end

  test "limit is clamped to the cap" do
    create_list(:terminal_session, 3, :running, :agent_session, user: @user, project: @project)

    assert_equal 1, ids(list(limit: 1)).size
    assert_operator ids(list(limit: 5_000)).size, :<=, InternalTools::SessionList::MAX_LIMIT
  end

  # == session_log ==

  test "reads a neighbour live and reports how long it has been silent" do
    @runtime.set_terminal_pane("compiling…\nstill compiling\n", last_output_at: 90.seconds.ago)
    neighbour = create(:terminal_session, :running, :agent_session, user: @user, project: @project)

    body = payload(log(neighbour))

    assert_equal "live", body["source"]
    assert_match(/still compiling/, body["log"])
    assert_in_delta 90, body["idle_seconds"], 5
  end

  test "the tail is short by default and capped when a bigger one is asked for" do
    @runtime.set_terminal_pane(Array.new(500) { |i| "line #{i}" }.join("\n"))
    neighbour = create(:terminal_session, :running, :agent_session, user: @user, project: @project)

    assert_equal InternalTools::SessionLog::DEFAULT_LINES, payload(log(neighbour))["log"].lines.size
    assert_equal InternalTools::SessionLog::MAX_LINES, payload(log(neighbour, lines: 5_000))["log"].lines.size
  end

  test "a quota error in the tail is surfaced as a verdict" do
    @runtime.set_terminal_pane("API Error: Your credit balance is too low to run this request\n")
    neighbour = create(:terminal_session, :running, :agent_session, user: @user, project: @project)

    assert payload(log(neighbour))["quota_error"].present?
  end

  test "a session in another project cannot be read" do
    other_project = create(:project, company: @company, owner: @user)
    theirs = create(:terminal_session, :running, :agent_session, user: @user, project: other_project)

    result = log(theirs)

    assert_equal 1, result[:exit_code]
    assert_match(/not found in this project/, result[:stderr])
  end

  test "a session its owner keeps private cannot be read" do
    other = create(:user)
    create(:company_membership, user: other, company: @company, role: :employee)
    theirs = create(:terminal_session, :running, :agent_session, user: other, project: @project)

    result = log(theirs)

    assert_equal 1, result[:exit_code]
    assert_match(/not found in this project/, result[:stderr])
  end
end
