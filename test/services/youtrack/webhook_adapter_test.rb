# frozen_string_literal: true

require "test_helper"

class Youtrack::WebhookAdapterTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @integration = create(:integration, :active, provider: :youtrack, company: @project.company,
      settings: { "base_url" => "https://youtrack.example.com/youtrack", "youtrack_project_id" => "0-1",
        "bot_login" => "bot", "bot_user_id" => "user-1" })
    @binding = create(:trigger_binding, project: @project, workflow: @workflow, integration: @integration,
      created_by: @user, event_type: "youtrack.issue.created")
    @endpoint = create(:webhook_endpoint, company: @project.company, provider: :youtrack,
      config: { "integration_id" => @integration.id })
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @adapter = Youtrack::WebhookAdapter.new
    @event = create(:trigger_event, project: @project, event_type: "youtrack.issue.created",
      data: { "integration_id" => @integration.id, "issue_id" => "2-1", "issue_readable_id" => "APP-1",
        "youtrack_project_id" => "0-1" })
  end

  test "normalized context retains safe issue and linked task URLs with bounded text" do
    payload = { "event" => "issueCreated", "issue" => { "id" => "2-1", "idReadable" => "APP-1",
      "summary" => "s" * 800, "description" => "d" * 800, "project" => { "id" => "0-1" } } }
    redacted = @adapter.redact(payload, @event.event_type, @integration)
    received = ReceivedWebhook.new(webhook_endpoint: @endpoint, raw_payload: redacted)
    @event.data = @adapter.normalize(received)[:data]
    task = create_task(description: "t" * 800)
    context = @adapter.run_context(@event, task).fetch("youtrack")

    assert_equal "https://youtrack.example.com/youtrack/issue/APP-1", context["issue_url"]
    assert_equal "issueCreated", context["source_event"]
    assert_includes context.dig("linked_task", "url"), "/company/projects/#{@project.id}/board?task=#{task.id}"
    %w[summary description text].each { |key| assert_operator context[key].length, :<=, 500 }
    assert_operator context.dig("linked_task", "description").length, :<=, 500
    assert_includes context["description"], "[truncated]"
  end

  test "mentions require username boundaries and exclude the connected author" do
    payload = { "event" => "commentAdded", "issue" => { "id" => "2-1", "idReadable" => "APP-1",
      "project" => { "id" => "0-1" } }, "comment" => { "id" => "4-1", "text" => "hello @bot",
        "author" => { "id" => "user-2" } } }
    type = @adapter.classify(payload)
    assert @adapter.redact(payload, type, @integration)
    payload["comment"]["text"] = "hello @bot-other"
    assert_nil @adapter.redact(payload, type, @integration)
    payload["comment"]["text"] = "hello @bot"
    payload["comment"]["author"]["id"] = "user-1"
    assert_nil @adapter.redact(payload, type, @integration)
  end

  test "subject lookup survives reconnect and company project overlap but excludes other projects and archives" do
    task = create_task
    @adapter.record_subject!(task, @binding, @event)
    replacement = create(:integration, :active, provider: :youtrack, company: @project.company,
      project: @project, settings: @integration.settings)
    @binding.update!(integration: replacement)
    Integrations::DisconnectService.call(@integration)

    assert_equal task, @adapter.find_subject(@binding.reload, @event)
    assert_equal 1, task.external_resources.count
    task.update!(archived_at: Time.current)
    assert_nil @adapter.find_subject(@binding, @event)

    other_project = create(:project, company: @project.company, owner: @user)
    @board = create(:board, project: other_project)
    @column = create(:board_column, board: @board)
    other_task = create_task
    @adapter.record_subject!(other_task, @binding, @event)
    assert_nil @adapter.find_subject(@binding, @event)
  end

  test "subject lookup prefers oldest same workflow link and rejects ambiguous cross workflow links" do
    first = create_task
    second = create_task
    @adapter.record_subject!(first, @binding, @event)
    @adapter.record_subject!(second, @binding, @event)
    assert_equal first, @adapter.find_subject(@binding, @event)

    @binding.update!(workflow: create(:workflow, scope: @project))
    assert_nil @adapter.find_subject(@binding, @event)
    second.update!(archived_at: Time.current)
    assert_equal first, @adapter.find_subject(@binding, @event)
  end

  test "company event fans out once per binding and replay preserves tasks and links" do
    mock_workflow_execution_start
    @binding.update!(subject_policy: :create_task, subject_column: @column)
    other_project = create(:project, company: @project.company, owner: @user)
    other_board = create(:board, project: other_project)
    other_column = create(:board_column, board: other_board)
    other_workflow = create(:workflow, scope: other_project)
    create(:trigger_binding, project: other_project, workflow: other_workflow, created_by: @user,
      integration: @integration, event_type: @event.event_type,
      subject_policy: :create_task, subject_column: other_column)
    @event.update!(project: nil, company: @project.company, relay_state: "pending")

    assert_difference -> { BoardTask.count }, 2 do
      assert_difference -> { ExternalResource.count }, 2 do
        assert_difference -> { WorkflowRun.count }, 2 do
          TriggerEngine.dispatch_pending(@event)
        end
      end
    end
    assert_equal "dispatched", @event.reload.relay_state
    @event.update!(relay_state: "pending")
    assert_no_difference [ "BoardTask.count", "ExternalResource.count", "WorkflowRun.count" ] do
      TriggerEngine.dispatch_pending(@event)
    end
    assert_equal 2, TriggerDispatch.where(trigger_event: @event, status: "started").count
  end

  private

  def create_task(**attributes)
    create(:board_task, board: @board, board_column: @column, **attributes)
  end
end
