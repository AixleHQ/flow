# frozen_string_literal: true

require "test_helper"

class InternalTools::SlackPostMessageTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = Integration.create!(
      provider: :slack, company: @company, project: @project, connected_by: @user,
      name: "Acme", status: :active
    )
    @integration.update!(credentials_data: { "bot_token" => "xoxb-1", "team_id" => "T1" })

    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
      shared_context: { "slack" => { "channel" => "C1", "thread_ts" => "111.2", "integration_id" => @integration.id } })
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)
    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "x")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  def run_tool(params)
    InternalTools::SlackPostMessage.new(params: params, session: @session).execute
  end

  test "posts to the triggering channel/thread by default" do
    Slack::Client.expects(:post_message)
      .with(has_entries(token: "xoxb-1", channel: "C1", text: "hi", thread_ts: "111.2"))
      .once.returns({ "ok" => true })

    result = run_tool(text: "hi")
    assert_equal 0, result[:exit_code]
  end

  test "uses an explicit channel and thread when provided" do
    Slack::Client.expects(:post_message)
      .with(has_entries(channel: "C2", thread_ts: "999"))
      .once.returns({ "ok" => true })

    assert_equal 0, run_tool(text: "hi", channel: "C2", thread_ts: "999")[:exit_code]
  end

  test "errors when neither text nor files are given" do
    Slack::Client.expects(:post_message).never
    Slack::Client.expects(:upload_files).never
    result = run_tool(text: "")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "text` and/or `files"
  end

  test "sends text and a file as a single message via the upload flow" do
    Slack::Client.expects(:upload_files)
      .with(has_entries(token: "xoxb-1", channel: "C1", thread_ts: "111.2", initial_comment: "here you go",
                        files: [ { filename: "fizzbuzz.rb", content: "puts 'Fizz'", title: nil } ]))
      .once.returns({ "ok" => true })
    Slack::Client.expects(:post_message).never

    result = run_tool(text: "here you go",
      files: [ { "filename" => "fizzbuzz.rb", "content" => "puts 'Fizz'" } ])
    assert_equal 0, result[:exit_code]
  end

  test "can send files only, with no text" do
    Slack::Client.expects(:upload_files)
      .with(has_entries(initial_comment: nil, files: [ { filename: "a.txt", content: "x", title: nil } ]))
      .once.returns({ "ok" => true })

    assert_equal 0, run_tool(files: [ { "filename" => "a.txt", "content" => "x" } ])[:exit_code]
  end

  test "errors when the project has no active Slack integration" do
    @integration.update!(status: :inactive)
    Slack::Client.expects(:post_message).never
    result = run_tool(text: "hi")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Slack is not connected"
  end

  test "errors when no channel is given and the run did not come from Slack" do
    @workflow_run.update!(shared_context: {})
    Slack::Client.expects(:post_message).never
    result = run_tool(text: "hi")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No channel"
  end

  test "replies through the workspace that triggered the run (by integration_id)" do
    other = Integration.create!(provider: :slack, company: @company, project: nil,
      connected_by: @user, name: "WS Two", status: :active)
    other.update!(credentials_data: { "bot_token" => "xoxb-OTHER", "team_id" => "T2" })
    @workflow_run.update!(shared_context: {
      "slack" => { "channel" => "C9", "thread_ts" => "9.9", "integration_id" => other.id }
    })

    Slack::Client.expects(:post_message)
      .with(has_entries(token: "xoxb-OTHER", channel: "C9", thread_ts: "9.9"))
      .once.returns({ "ok" => true })

    assert_equal 0, run_tool(text: "hi")[:exit_code]
  end
end
