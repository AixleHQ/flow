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

    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user,
      shared_context: { "slack" => { "channel" => "C1", "thread_ts" => "111.2", "integration_id" => @integration.id } })
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)
    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "x")
    @step_run.update!(terminal_session: @session)
    @session.reload

    stub_slack_client!
  end

  def run_tool(params)
    InternalTools::SlackPostMessage.new(params: params, session: @session).execute
  end

  test "posts to the triggering channel/thread by default" do
    result = run_tool(text: "hi")
    assert_equal 0, result[:exit_code]

    assert_equal 1, fake_slack.posted_messages.size
    msg = fake_slack.last_posted_message
    assert_equal "xoxb-1", msg[:token]
    assert_equal "C1", msg[:channel]
    assert_equal "hi", msg[:text]
    assert_equal "111.2", msg[:thread_ts]
  end

  test "uses an explicit channel and thread when provided" do
    assert_equal 0, run_tool(text: "hi", channel: "C2", thread_ts: "999")[:exit_code]

    assert_equal 1, fake_slack.posted_messages.size
    msg = fake_slack.last_posted_message
    assert_equal "C2", msg[:channel]
    assert_equal "999", msg[:thread_ts]
  end

  test "errors when neither text nor files are given" do
    result = run_tool(text: "")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "text` and/or `files"

    assert_empty fake_slack.posted_messages
    assert_empty fake_slack.uploaded_files
  end

  test "sends text and a file as a single message via the upload flow" do
    result = run_tool(text: "here you go",
      files: [ { "filename" => "fizzbuzz.rb", "content" => "puts 'Fizz'" } ])
    assert_equal 0, result[:exit_code]

    assert_equal 1, fake_slack.uploaded_files.size
    upload = fake_slack.last_uploaded_files
    assert_equal "xoxb-1", upload[:token]
    assert_equal "C1", upload[:channel]
    assert_equal "111.2", upload[:thread_ts]
    assert_equal "here you go", upload[:initial_comment]
    assert_equal [ { filename: "fizzbuzz.rb", content: "puts 'Fizz'", title: nil } ], upload[:files]

    assert_empty fake_slack.posted_messages
  end

  test "can send files only, with no text" do
    assert_equal 0, run_tool(files: [ { "filename" => "a.txt", "content" => "x" } ])[:exit_code]

    assert_equal 1, fake_slack.uploaded_files.size
    upload = fake_slack.last_uploaded_files
    assert_nil upload[:initial_comment]
    assert_equal [ { filename: "a.txt", content: "x", title: nil } ], upload[:files]
  end

  test "sends multiple files of mixed sources in one message" do
    runtime = stub_container_runtime
    runtime.fs["/workspace/outputs/chart.png"] = "\x89PNG\r\n\x1a\nBINARY".b
    @session.update!(container_id: "c-123")
    asset = create(:asset, scope: @project, created_by: @user, name: "spec.pdf")
    create(:asset_version, asset: asset, uploaded_by: @user,
      file: AssetFileUploader.upload(StringIO.new("%PDF-1.4 bytes"), :store))

    result = run_tool(text: "batch", files: [
      { "filename" => "notes.txt", "content" => "hi" },
      { "file_path" => "/workspace/outputs/chart.png", "title" => "Chart" },
      { "asset_id" => asset.id }
    ])
    assert_equal 0, result[:exit_code]

    upload = fake_slack.last_uploaded_files
    assert_equal "batch", upload[:initial_comment]
    assert_equal(
      [
        { filename: "notes.txt", content: "hi", title: nil },
        { filename: "chart.png", content: "\x89PNG\r\n\x1a\nBINARY".b, title: "Chart" },
        { filename: "spec.pdf", content: "%PDF-1.4 bytes", title: nil }
      ],
      upload[:files]
    )
  end

  test "reads a binary file from the container by file_path" do
    runtime = stub_container_runtime
    runtime.fs["/workspace/outputs/logo.png"] = "\x00\x01\x02binary".b
    @session.update!(container_id: "c-9")

    assert_equal 0, run_tool(files: [ { "file_path" => "/workspace/outputs/logo.png" } ])[:exit_code]

    upload = fake_slack.last_uploaded_files
    assert_equal [ { filename: "logo.png", content: "\x00\x01\x02binary".b, title: nil } ], upload[:files]
  end

  test "errors when a file_path is not present in the container" do
    stub_container_runtime
    @session.update!(container_id: "c-9")

    result = run_tool(files: [ { "file_path" => "/workspace/outputs/missing.png" } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found in container"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when a file_path is given but the session has no container" do
    @session.update!(container_id: nil)

    result = run_tool(files: [ { "file_path" => "/workspace/outputs/x.png" } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No container available"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when an asset_id is not in the project" do
    other = create(:asset, :with_company_scope, created_by: @user)

    result = run_tool(files: [ { "asset_id" => other.id } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "asset not found"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when a file entry sets more than one source" do
    result = run_tool(files: [ { "filename" => "a.txt", "content" => "x", "file_path" => "/p" } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "only one of"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when a file entry sets no source" do
    result = run_tool(files: [ { "title" => "orphan" } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "needs one of"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when inline content is missing a filename" do
    result = run_tool(files: [ { "content" => "x" } ])
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "requires filename"
    assert_empty fake_slack.uploaded_files
  end

  test "errors when the project has no active Slack integration" do
    @integration.update!(status: :inactive)
    result = run_tool(text: "hi")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Slack is not connected"

    assert_empty fake_slack.posted_messages
  end

  test "errors when no channel is given and the run did not come from Slack" do
    @workflow_run.update!(shared_context: {})
    result = run_tool(text: "hi")
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No channel"

    assert_empty fake_slack.posted_messages
  end

  test "replies through the workspace that triggered the run (by integration_id)" do
    other = Integration.create!(provider: :slack, company: @company, project: nil,
      connected_by: @user, name: "WS Two", status: :active)
    other.update!(credentials_data: { "bot_token" => "xoxb-OTHER", "team_id" => "T2" })
    @workflow_run.update!(shared_context: {
      "slack" => { "channel" => "C9", "thread_ts" => "9.9", "integration_id" => other.id }
    })

    assert_equal 0, run_tool(text: "hi")[:exit_code]

    assert_equal 1, fake_slack.posted_messages.size
    msg = fake_slack.last_posted_message
    assert_equal "xoxb-OTHER", msg[:token]
    assert_equal "C9", msg[:channel]
    assert_equal "9.9", msg[:thread_ts]
  end
end
