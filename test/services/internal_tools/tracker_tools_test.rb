# frozen_string_literal: true

require "test_helper"

class InternalTools::TrackerToolsTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @tracker = create(:project_tracker, :primary, integration: @integration, handle: "boards")
    @fakes = stub_azure_devops!(integration: @integration)

    board = create(:board, project: @project)
    column = create(:board_column, board: board, name: "Backlog", position: 1)
    @task = create(:board_task, board: board, board_column: column)
    @workflow = create(:workflow, scope: @project)
    @workflow_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, board_task: @task)
    step_run = create(:step_run, workflow_run: @workflow_run, step: create(:step, workflow: @workflow))
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
    step_run.update!(terminal_session: @session)
    @session.reload
  end

  def run_tool(klass, **params)
    klass.new(params: params, session: @session).execute
  end

  def tool_ok(result)
    assert_equal 0, result[:exit_code], result[:stderr]
    JSON.parse(result[:stdout])
  end

  def tool_error(result)
    assert_equal 1, result[:exit_code], result[:stdout]
    JSON.parse(result[:stderr])
  end

  # A second Azure project on the same connection: the fakes answer for one integration.
  def second_tracker(**attributes)
    first = @integration.azure_project_ids.first
    extra = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: [ first, extra ])
    @integration.update!(settings: @integration.settings.merge(
      "azure_project_ids" => [ first, extra ], "azure_project_names" => { first => "Customer Platform", extra => "Legacy" }
    ))
    create(:project_tracker, integration: @integration, external_scope_id: extra, name: "Legacy", handle: "legacy",
                             **attributes)
  end

  test "tracker_list shows the project's trackers and which one started the run" do
    @workflow_run.update!(shared_context: { "tracker" => { "project_tracker_id" => @tracker.id } })

    trackers = tool_ok(run_tool(InternalTools::TrackerList))["trackers"]

    assert_equal [ "boards" ], trackers.pluck("handle")
    assert_equal true, trackers.first["started_this_run"] # rubocop:disable Minitest/AssertTruthy
    assert_equal true, trackers.first["primary"] # rubocop:disable Minitest/AssertTruthy
  end

  test "a call without `tracker` goes to the primary tracker, and a named one to that tracker" do
    legacy = second_tracker

    assert_equal "boards", tool_ok(run_tool(InternalTools::TrackerGetIssue, issue: "11"))["tracker"]
    assert_equal "legacy", tool_ok(run_tool(InternalTools::TrackerGetIssue, issue: "11", tracker: legacy.handle))["tracker"]
    assert_equal "not_found", tool_error(run_tool(InternalTools::TrackerGetIssue, issue: "11", tracker: "nope"))["error"]
  end

  test "several trackers and no primary is an error naming them, never the first row" do
    @tracker.update!(primary: false)
    second_tracker

    error = tool_error(run_tool(InternalTools::TrackerGetIssue, issue: "11"))

    assert_equal "tracker_required", error["error"]
    assert_equal %w[boards legacy], error.dig("details", "trackers")
  end

  test "a run started by a tracker stays on it, and fails closed once it is detached" do
    legacy = second_tracker
    @workflow_run.update!(shared_context: { "tracker" => { "project_tracker_id" => legacy.id } })

    assert_equal "legacy", tool_ok(run_tool(InternalTools::TrackerGetIssue, issue: "11"))["tracker"]

    legacy.detach!
    assert_equal "tracker_unavailable", tool_error(run_tool(InternalTools::TrackerGetIssue, issue: "11"))["error"]
  end

  test "a read-only tracker refuses writes and points at the primary one" do
    legacy = second_tracker(access: "read_only")

    error = tool_error(run_tool(InternalTools::TrackerAddComment, tracker: legacy.handle, issue: "11", body: "x"))

    assert_equal "read_only", error["error"]
    assert_match(/primary tracker is 'boards'/, error["message"])
    assert_empty @fakes.work_items.calls_to(:add_comment)
  end

  test "creating an issue records who wrote it and links it to the run's task" do
    @workflow_run.update!(shared_context: { "tracker" => { "chain" => [ 7 ] } })

    created = tool_ok(run_tool(InternalTools::TrackerCreateIssue, type: "Bug", title: "It breaks"))

    operation = TrackerOperation.sole
    assert_equal "create_issue", operation.operation
    assert_equal "succeeded", operation.state
    assert_equal [ @workflow_run.id, @workflow.id, [ 7 ], "11" ],
                 [ operation.workflow_run_id, operation.workflow_id, operation.chain, operation.issue_id ]
    assert_equal operation.operation_key, created["operation_key"]

    link = @task.external_resources.sole
    assert_equal [ "azure_devops", "11", @tracker.id ], [ link.provider, link.external_id, link.data["project_tracker_id"] ]
  end

  test "an identical retry in the same session replays the first result instead of filing twice" do
    first = tool_ok(run_tool(InternalTools::TrackerCreateIssue, type: "Bug", title: "It breaks"))
    second = tool_ok(run_tool(InternalTools::TrackerCreateIssue, type: "Bug", title: "It breaks"))

    assert_equal 1, @fakes.work_items.calls_to(:create).size
    assert_equal first["operation_key"], second["operation_key"]
    assert_equal true, second["replayed"] # rubocop:disable Minitest/AssertTruthy
  end

  test "an operation_key reused for a different request is a conflict" do
    tool_ok(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "one", operation_key: "k1"))

    error = tool_error(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "two", operation_key: "k1"))

    assert_equal "conflict", error["error"]
    assert_equal 1, @fakes.work_items.calls_to(:add_comment).size
  end

  test "a write the tracker refused can be retried, one that was never answered cannot" do
    @fakes.work_items.instance_variable_set(:@error, AzureDevops::RateLimited.new("slow down"))
    assert_equal "rate_limited", tool_error(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "x"))["error"]

    @fakes.work_items.instance_variable_set(:@error, nil)
    tool_ok(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "x"))
    assert_equal "succeeded", TrackerOperation.sole.state

    @fakes.work_items.instance_variable_set(:@error, AzureDevops::OutcomeUnknown.new("no answer"))
    assert_equal "outcome_unknown", tool_error(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "y"))["error"]
    @fakes.work_items.instance_variable_set(:@error, nil)
    assert_equal "outcome_unknown", tool_error(run_tool(InternalTools::TrackerAddComment, issue: "11", body: "y"))["error"]
    assert_equal 1, @fakes.work_items.calls_to(:add_comment).size
  end

  test "transitioning records the status change the tracker event will be matched against" do
    tool_ok(run_tool(InternalTools::TrackerTransitionIssue, issue: "11", status: "Resolved"))

    assert_equal({ "field" => "status", "to" => "Resolved" }, TrackerOperation.sole.change)
  end

  test "tracker_link_task links the run's task without writing to the tracker" do
    linked = tool_ok(run_tool(InternalTools::TrackerLinkTask, issue: "11"))

    assert_equal @task.id, linked["task_id"]
    assert_equal "11", @task.external_resources.sole.external_id
    assert_empty @fakes.work_items.calls_to(:update)
    tool_ok(run_tool(InternalTools::TrackerLinkTask, issue: "11"))
    assert_equal 1, @task.external_resources.count
  end

  test "the tools are offered only while the project has a usable tracker" do
    tool = Tool.shadow_for(Tools::Registry.fetch("tracker_get_issue"))

    assert_includes Tool.visible_for_project(@project), tool
    assert tool.available?(Tools::Context.for_session(@session))

    @tracker.detach!
    refute_includes Tool.visible_for_project(@project), tool
    refute tool.available?(Tools::Context.for_session(@session))
  end

  test "tracker_list_users says so on a tracker that cannot list its users" do
    assert_equal "unsupported", tool_error(run_tool(InternalTools::TrackerListUsers, query: "ada"))["error"]
  end
end
