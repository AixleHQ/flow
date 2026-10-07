# frozen_string_literal: true

require "test_helper"

# Starting a workflow from Teams as the linked person: "Run workflow" on a
# message, /run and /status (docs/design/teams-integration.md §20).
class Teams::RunActionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SENDER = "b130c271-0000-4000-8000-000000000001"

  setup do
    with_teams_enabled
    stub_teams_token!
    @user = create(:user, :with_company, name: "Ada Lovelace")
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company, name: "Sales Ops")
    @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
    create(:step, workflow: @workflow, name: "Render", position: 1, allow_non_interactive: true)
    manual = create(:workflow, scope: @project, name: "Needs a person")
    create(:step, workflow: manual, name: "Review", position: 1, allow_non_interactive: false)
    @integration = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                       status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    @conversation = ChatConversation.record_teams!(integration: @integration, activity: teams_activity)
    @channel = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2/activities"
  end

  def link_sender!
    ChatIdentity.create!(provider: "teams", workspace_id: TEAMS_CUSTOMER_TENANT, external_user_id: SENDER, user: @user,
                         proof: "microsoft_sign_in", linked_at: Time.current)
  end

  def invoke(name, value, id: "f:invoke-1")
    teams_activity(mention: false).merge("type" => "invoke", "name" => name, "id" => id, "value" => value)
  end

  def message_payload
    { "id" => "1700000000005", "replyToId" => "1700000000001", "linkToMessage" => "https://teams.microsoft.com/l/message/x",
      "body" => { "contentType" => "html", "content" => "<p>Customer&nbsp;Acme asks for the Q3 digest</p>" } }
  end

  def expect_run(**context)
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    WorkflowService.expects(:enqueue).with(has_entries(workflow: @workflow, user: @user, mode: :non_interactive,
                                                       shared_context: has_entries("chat" => has_entries(context))))
                   .once.returns(run)
    WorkflowService.stubs(:dispatch_or_leave_to_relay)
    run
  end

  def card_of(response) = response.dig(:task, :value, :card, :content)

  def notice_of(response) = card_of(response).dig(:body, 0, :text)

  test "a person not linked yet is offered the link instead of the workflows" do
    response = Teams::RunAction.fetch(@integration, invoke("composeExtension/fetchTask",
                                                           { "commandId" => "runWorkflow", "messagePayload" => message_payload }))

    action = card_of(response)[:actions].sole
    assert_equal "Action.OpenUrl", action[:type]
    claim = Teams::AccountLink.claim(URI.parse(action[:url]).path.split("/").last)
    assert_equal [ TEAMS_CUSTOMER_TENANT, SENDER ], claim.values_at("tid", "oid")
  end

  test "a linked person picks among the workflows they may start that can run unattended" do
    link_sender!

    response = Teams::RunAction.fetch(@integration, invoke("composeExtension/fetchTask",
                                                           { "commandId" => "runWorkflow", "messagePayload" => message_payload }))

    choices = card_of(response)[:body].find { |element| element[:id] == "workflow" }[:choices]
    assert_equal [ { title: "Weekly Digest — Sales Ops", value: "#{@project.id}:#{@workflow.id}" } ], choices
    assert_equal "Customer Acme asks for the Q3 digest", card_of(response)[:actions].sole.dig(:data, "text")
  end

  test "submitting the dialog starts the workflow as the linked person, on that message's thread" do
    link_sender!
    run = expect_run("provider" => "teams", "thread_id" => "1700000000001", "message_id" => "1700000000005",
                     "text" => "Customer Acme asks for the Q3 digest\n\nNotes: for the board")

    response = Teams::RunAction.submit(@integration, invoke("composeExtension/submitAction", {
      "commandId" => "runWorkflow",
      "data" => { "workflow" => "#{@project.id}:#{@workflow.id}", "notes" => "for the board", "message_id" => "1700000000005",
                  "reply_to" => "1700000000001", "text" => "Customer Acme asks for the Q3 digest" }
    }))

    assert_equal({}, response)
    dispatch = TriggerDispatch.find_by!(workflow_run: run)
    assert_equal Chat::ACTION_SOURCE, dispatch.source
    assert Chat::RunStatusReporter.applies?(dispatch, "running")
    assert_enqueued_with(job: Triggers::ReportRunTransitionJob, args: [ dispatch.id, "dispatched" ])
  end

  test "Teams retrying a slow submit starts one run" do
    link_sender!
    expect_run
    data = { "workflow" => "#{@project.id}:#{@workflow.id}", "message_id" => "1700000000005", "text" => "go" }

    2.times { Teams::RunAction.submit(@integration, invoke("composeExtension/submitAction", { "data" => data })) }

    assert_equal 1, TriggerDispatch.count
  end

  test "a workflow outside what the person may start is refused" do
    link_sender!
    outsider = create(:project, owner: create(:user, company: @company), company: @company)
    hidden = create(:workflow, scope: outsider)

    response = Teams::RunAction.submit(@integration, invoke("composeExtension/submitAction",
                                                            { "data" => { "workflow" => "#{outsider.id}:#{hidden.id}" } }))

    assert_match(/can't start that workflow/, notice_of(response))
    assert_equal 0, TriggerDispatch.count
  end

  test "/run's card starts the run in a thread of its own that says who started it" do
    link_sender!
    opened = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations").with { |request|
      JSON.parse(request.body).dig("activity", "text") == "▶️ **Ada Lovelace** started **Weekly Digest**"
    }.to_return(status: 201, body: { id: "19:abc@thread.tacv2;messageid=1700000000900", activityId: "1700000000900" }.to_json)
    expect_run("thread_id" => "1700000000900", "text" => "/run")

    response = Teams::RunAction.execute(@integration, invoke("adaptiveCard/action", {
      "action" => { "type" => "Action.Execute", "verb" => "run", "data" => { "workflow" => "#{@project.id}:#{@workflow.id}" } }
    }))

    assert_requested opened
    assert_equal "application/vnd.microsoft.card.adaptive", response[:type]
    assert_match(/Started Weekly Digest · run #\d+/, response.dig(:value, :body, 0, :text))
  end

  test "/run privately offers the picker, and /status lists the runs started here" do
    link_sender!
    create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, shared_context: {
      "chat" => { "provider" => "teams", "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" } }
    })
    picker = stub_request(:post, "#{@channel}?isTargetedActivity=true").with { |request|
      JSON.parse(request.body).dig("attachments", 0, "content", "actions", 0, "verb") == "run"
    }.to_return(status: 201, body: { id: "1" }.to_json)
    status = stub_request(:post, "#{@channel}?isTargetedActivity=true").with { |request|
      JSON.parse(request.body).dig("attachments", 0, "content", "body", 0, "text").to_s.include?("▶️ Running — **Weekly Digest**")
    }.to_return(status: 201, body: { id: "2" }.to_json)

    %w[run status].each do |text|
      event = TriggerEvent.create!(event_type: "chat.message", source: "teams:teams-tenant-#{TEAMS_CUSTOMER_TENANT}",
                                   company: @company, occurred_at: Time.current, data: {
                                     "provider" => "teams", "integration_id" => @integration.id, "targeted" => true,
                                     "workspace" => { "id" => TEAMS_CUSTOMER_TENANT }, "actor" => { "id" => SENDER },
                                     "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" },
                                     "requester" => { "id" => "29:user" }, "message_id" => "1700000000009", "text" => text
                                   })
      WorkflowService.expects(:enqueue).never
      TriggerEngine.dispatch(event)
    end

    assert_requested picker
    assert_requested status
  end

  test "a linked account that may no longer sign in starts nothing and is asked to link again" do
    link_sender!
    @user.soft_delete!

    response = Teams::RunAction.fetch(@integration, invoke("composeExtension/fetchTask",
                                                           { "commandId" => "runWorkflow", "messagePayload" => message_payload }))

    assert_equal "Link your Aixle account", response.dig(:task, :value, :title)
    assert_nil Teams::Sender.user_id(TEAMS_CUSTOMER_TENANT, SENDER)
  end

  test "a linked person outside the connected company is offered nothing to start" do
    stranger = create(:user, :with_company)
    ChatIdentity.create!(provider: "teams", workspace_id: TEAMS_CUSTOMER_TENANT, external_user_id: SENDER, user: stranger,
                         proof: "microsoft_sign_in", linked_at: Time.current)

    response = Teams::RunAction.fetch(@integration, invoke("composeExtension/fetchTask",
                                                           { "commandId" => "runWorkflow", "messagePayload" => message_payload }))

    assert_match(/no workflow you can start/, notice_of(response))
  end

  test "a retried /run click opens one thread, and a start that is refused takes its thread back" do
    link_sender!
    opened = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations")
             .to_return(status: 201, body: { id: "19:abc@thread.tacv2;messageid=1700000000900", activityId: "1700000000900" }.to_json)
    expect_run("thread_id" => "1700000000900")
    click = invoke("adaptiveCard/action", {
      "action" => { "type" => "Action.Execute", "verb" => "run", "data" => { "workflow" => "#{@project.id}:#{@workflow.id}" } }
    })

    2.times { Teams::RunAction.execute(@integration, click) }

    assert_requested opened, times: 1
    assert_equal 1, TriggerDispatch.count

    WorkflowService.unstub(:enqueue)
    WorkflowService.expects(:enqueue).returns(WorkflowRun.new)
    removed = stub_request(:delete, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000900/activities/1700000000900")
              .to_return(status: 200, body: "")

    response = Teams::RunAction.execute(@integration, click.merge("id" => "f:invoke-2"))

    assert_requested removed
    assert_match(/Weekly Digest did not start/, response.dig(:value, :body, 0, :text))
  end

  test "in a 1:1 chat only /run or the bare word is a command; a sentence goes to the triggers" do
    link_sender!
    direct = { "provider" => "teams", "integration_id" => @integration.id, "workspace" => { "id" => TEAMS_CUSTOMER_TENANT },
               "actor" => { "id" => SENDER }, "conversation" => { "id" => "a:1personal", "type" => "direct" } }

    assert_equal [ "run", "" ], Teams::Commands.command(TriggerEvent.new(data: direct.merge("text" => "/run")))
    assert_equal [ "status", "" ], Teams::Commands.command(TriggerEvent.new(data: direct.merge("text" => "status")))
    assert_nil Teams::Commands.command(TriggerEvent.new(data: direct.merge("text" => "run the Q3 digest")))
    assert_nil Teams::Commands.command(TriggerEvent.new(data: direct.merge("text" => "status report")))
  end

  test "/status from someone not linked offers the link, and lists no run of a project they cannot see" do
    hidden_project = create(:project, owner: create(:user, company: @company), company: @company)
    create(:workflow_run, workflow: create(:workflow, scope: hidden_project, name: "Secret"), project: hidden_project,
                          user: @user, shared_context: { "chat" => { "provider" => "teams", "conversation" => { "id" => "19:abc@thread.tacv2" } } })
    event = TriggerEvent.new(data: { "workspace" => { "id" => TEAMS_CUSTOMER_TENANT }, "actor" => { "id" => SENDER } })

    assert_equal "Action.OpenUrl", Teams::Commands.status_card(@integration, @conversation, event.data).dig(:actions, 0, :type)

    link_sender!
    text = Teams::Commands.status_card(@integration, @conversation, event.data).dig(:body, 0, :text)
    assert_equal "No runs were started from this conversation in the last 30 days.", text
  end

  test "the manifest offers Run workflow on a message, and run and status as slash commands" do
    manifest = Teams::AppPackage.manifest

    assert_equal [ "runWorkflow", "action", [ "message" ], true ],
                 manifest.dig("composeExtensions", 0, "commands", 0).values_at("id", "type", "context", "fetchTask")
    assert_equal [ %w[help], %w[run status] ],
                 manifest.dig("bots", 0, "commandLists").map { |list| list["commands"].pluck("title") }
  end

  test "a Teams trigger cannot claim run or status, a Slack one can" do
    teams = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_provider: "teams",
                                    filter_predicate: { "text" => "status" })
    slack = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                    filter_predicate: { "text" => "status" })

    assert_not teams.valid?
    assert_match(/Teams answers it as a command/, teams.errors[:filter_predicate].join)
    assert slack.valid?
  end
end
