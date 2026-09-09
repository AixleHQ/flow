# frozen_string_literal: true

require "test_helper"

# The Slack tools that act on a message that already exists: editing it, deleting
# it, and reading the thread it lives in. Posting is covered by
# InternalTools::SlackPostMessageTest.
class InternalTools::SlackMessageToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = Integration.create!(
      provider: :slack, company: @company, project: @project, connected_by: @user,
      name: "Acme", status: :active
    )
    @integration.update!(credentials_data: { "bot_token" => "xoxb-1", "team_id" => "T1" })

    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
      shared_context: { "slack" => {
        "channel" => "C1", "ts" => "111.5", "thread_ts" => "111.2", "integration_id" => @integration.id
      } })
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)
    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "x")
    @step_run.update!(terminal_session: @session)
    @session.reload

    stub_slack_client!
  end

  def update(params) = InternalTools::SlackUpdateMessage.new(params: params, session: @session).execute
  def delete(params) = InternalTools::SlackDeleteMessage.new(params: params, session: @session).execute
  def read_thread(params = {}) = InternalTools::SlackReadThread.new(params: params, session: @session).execute

  # --- slack_update_message --------------------------------------------------

  test "update edits the message in the triggering channel by default" do
    result = update(ts: "111.9", text: "done")
    assert_equal 0, result[:exit_code]

    edit = fake_slack.last_updated_message
    assert_equal "xoxb-1", edit[:token]
    assert_equal "C1", edit[:channel]
    assert_equal "111.9", edit[:ts]
    assert_equal "done", edit[:text]
    assert_nil edit[:blocks]
  end

  test "update replaces the message with blocks when given" do
    blocks = [ { "type" => "markdown", "text" => "**done**" } ]
    assert_equal 0, update(ts: "111.9", text: "done", channel: "C2", blocks: blocks)[:exit_code]

    edit = fake_slack.last_updated_message
    assert_equal "C2", edit[:channel]
    assert_equal blocks, edit[:blocks].map(&:to_h)
  end

  test "update needs something to replace the message with" do
    result = update(ts: "111.9")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Provide `text` and/or `blocks`"
    assert_empty fake_slack.updated_messages
  end

  test "update rejects interactive blocks like posting does" do
    result = update(ts: "111.9", blocks: [ { "type" => "actions", "elements" => [] } ])

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "interactivity endpoint"
    assert_empty fake_slack.updated_messages
  end

  test "update surfaces the Slack error code to the agent" do
    fake_slack.stubs(:update_message).raises(Slack::Client::Error.new("message_not_found"))

    result = update(ts: "111.9", text: "done")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "message_not_found"
  end

  test "update errors when Slack is not connected" do
    @integration.update!(status: :inactive)

    result = update(ts: "111.9", text: "done")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Slack is not connected"
    assert_empty fake_slack.updated_messages
  end

  # --- slack_delete_message --------------------------------------------------

  test "delete removes the message from the triggering channel by default" do
    result = delete(ts: "111.9")
    assert_equal 0, result[:exit_code]

    removed = fake_slack.last_deleted_message
    assert_equal "xoxb-1", removed[:token]
    assert_equal "C1", removed[:channel]
    assert_equal "111.9", removed[:ts]
  end

  test "delete uses an explicit channel when given" do
    assert_equal 0, delete(ts: "111.9", channel: "C2")[:exit_code]

    assert_equal "C2", fake_slack.last_deleted_message[:channel]
  end

  test "delete surfaces the Slack error code to the agent" do
    fake_slack.stubs(:delete_message).raises(Slack::Client::Error.new("cant_delete_message"))

    result = delete(ts: "111.9")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "cant_delete_message"
  end

  test "delete errors when no channel is known" do
    @workflow_run.update!(shared_context: {})

    result = delete(ts: "111.9")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No channel"
    assert_empty fake_slack.deleted_messages
  end

  # --- slack_read_thread -----------------------------------------------------

  test "read_thread reads the triggering thread with no arguments" do
    result = read_thread
    assert_equal 0, result[:exit_code]

    read = fake_slack.last_replies_read
    assert_equal "C1", read[:channel]
    assert_equal "111.2", read[:ts] # the thread, not the message that mentioned us
    assert_equal 50, read[:limit]

    payload = JSON.parse(result[:stdout])
    assert_equal 2, payload["messages"].size
    assert_equal "1700000000.000100", payload.dig("messages", 0, "ts")
    assert_equal "U00USER000", payload.dig("messages", 0, "user")
    assert_equal "B00000000", payload.dig("messages", 1, "bot_id")
    assert_not payload["has_more"]
    assert_nil payload["next_cursor"]
  end

  test "read_thread takes an explicit channel, thread and cursor" do
    assert_equal 0, read_thread(channel: "C2", thread_ts: "222.1", cursor: "page-2")[:exit_code]

    read = fake_slack.last_replies_read
    assert_equal "C2", read[:channel]
    assert_equal "222.1", read[:ts]
    assert_equal "page-2", read[:cursor]
  end

  test "read_thread clamps the limit to what Slack will serve" do
    read_thread(limit: 500)
    assert_equal 200, fake_slack.last_replies_read[:limit]

    read_thread(limit: 0)
    assert_equal 1, fake_slack.last_replies_read[:limit]
  end

  test "read_thread reports the cursor when the thread is longer than the page" do
    result = read_thread(limit: 1)

    payload = JSON.parse(result[:stdout])
    assert_equal 1, payload["messages"].size
    assert payload["has_more"]
    assert_equal "fake-cursor-1", payload["next_cursor"]
  end

  test "read_thread lists the names of files shared in the thread" do
    fake_slack.thread_messages = [
      { "ts" => "1.1", "user" => "U1", "text" => "see this",
        "files" => [ { "id" => "F1", "name" => "spec.pdf" } ] }
    ]

    payload = JSON.parse(read_thread[:stdout])

    assert_equal [ "spec.pdf" ], payload.dig("messages", 0, "files")
  end

  test "read_thread errors when the run did not come from a Slack thread" do
    @workflow_run.update!(shared_context: { "slack" => { "channel" => "C1" } })

    result = read_thread

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No thread given"
    assert_empty fake_slack.replies_reads
  end

  test "read_thread surfaces the Slack error code to the agent" do
    fake_slack.stubs(:conversation_replies).raises(Slack::Client::Error.new("thread_not_found"))

    result = read_thread

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "thread_not_found"
  end

  # --- outside a workflow run ------------------------------------------------
  #
  # Attached by hand to a plain agent session, these work off the session's
  # project; only the trigger-derived channel/thread defaults are missing.

  test "update and delete work in a plain agent session with an explicit channel" do
    assert_equal 0, InternalTools::SlackUpdateMessage.new(
      params: { ts: "111.9", text: "done", channel: "C7" }, session: plain_session
    ).execute[:exit_code]
    assert_equal "C7", fake_slack.last_updated_message[:channel]

    assert_equal 0, InternalTools::SlackDeleteMessage.new(
      params: { ts: "111.9", channel: "C7" }, session: plain_session
    ).execute[:exit_code]
    assert_equal "C7", fake_slack.last_deleted_message[:channel]
  end

  test "read_thread in a plain agent session needs both coordinates named" do
    no_channel = InternalTools::SlackReadThread.new(params: { thread_ts: "1.1" }, session: plain_session).execute
    assert_equal 1, no_channel[:exit_code]
    assert_includes no_channel[:stderr], "pass `channel` explicitly"

    no_thread = InternalTools::SlackReadThread.new(params: { channel: "C7" }, session: plain_session).execute
    assert_equal 1, no_thread[:exit_code]
    assert_includes no_thread[:stderr], "No thread given"

    assert_empty fake_slack.replies_reads

    ok = InternalTools::SlackReadThread.new(
      params: { channel: "C7", thread_ts: "1.1" }, session: plain_session
    ).execute
    assert_equal 0, ok[:exit_code]
    assert_equal "C7", fake_slack.last_replies_read[:channel]
  end

  # An agent session in the same project, with no step_run and so no workflow run.
  def plain_session
    @plain_session ||= create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "x")
  end
end
