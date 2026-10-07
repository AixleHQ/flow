# frozen_string_literal: true

require "test_helper"

# The chat_* tools against both messengers: Slack through its fake client, Teams
# through WebMock at the Connector and Graph.
class InternalTools::ChatToolsTest < ActiveSupport::TestCase
  GRAPH = "https://graph.microsoft.com/v1.0"

  setup do
    with_teams_enabled
    stub_teams_token!
    stub_teams_token!(tenant: TEAMS_CUSTOMER_TENANT, token: "graph-token")
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @teams = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                 status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    @channel = ChatConversation.record_teams!(integration: @teams, activity: teams_activity)
    @channel.update!(team_aad_group_id: "1b22f251-0000-4000-8000-000000000001")
    @thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
    origin = Chat::TeamsProvider.run_context(TriggerEvent.new(data: {
      "provider" => "teams", "integration_id" => @teams.id, "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" },
      "thread_id" => "1700000000001", "message_id" => "1700000000002", "raw_text" => "deploy"
    }))
    @session = session_for(origin)
  end

  def session_for(shared_context)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, shared_context: shared_context)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
    session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                  mode: "non_interactive", initial_prompt: "x")
    step_run.update!(terminal_session: session)
    session.reload
  end

  def run_tool(klass, params = {}, session: @session, **more)
    klass.new(params: params.merge(more), session: session).execute
  end

  test "posting from a Teams-started run answers in its thread as Markdown" do
    posted = stub_request(:post, @thread)
             .with(body: hash_including("textFormat" => "markdown", "text" => "**Done**"))
             .to_return(status: 201, body: { id: "1700000000777" }.to_json)

    result = run_tool(InternalTools::ChatPostMessage, text: "**Done**")

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_requested posted
    assert_equal({ "provider" => "teams", "conversation" => "19:abc@thread.tacv2", "thread" => "1700000000001",
                   "message_id" => "1700000000777" }, JSON.parse(result[:stdout]))
  end

  test "a new thread in a channel, named by team and channel" do
    started = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations")
              .with(body: hash_including("channelData" => { "channel" => { "id" => "19:abc@thread.tacv2" },
                                                            "tenant" => { "id" => TEAMS_CUSTOMER_TENANT } }))
              .to_return(status: 201, body: { id: "19:abc@thread.tacv2;messageid=1700000000900", activityId: "1700000000900" }.to_json)

    result = run_tool(InternalTools::ChatPostMessage, text: "Weekly report", conversation: "Sales/Onboarding", new_thread: true)

    assert_requested started
    assert_equal [ "1700000000900", "1700000000900" ], JSON.parse(result[:stdout]).values_at("thread", "message_id")
  end

  test "a conversation outside the project's company is never reached" do
    other = Integration.create!(provider: :teams, company: create(:company), connected_by: create(:user), name: "Other",
                                status: :active)
    foreign = other.chat_conversations.create!(provider: "teams", external_id: "19:foreign@thread.tacv2", kind: "channel",
                                               service_url: TEAMS_SERVICE_URL, tenant_id: TEAMS_CUSTOMER_TENANT)

    result = run_tool(InternalTools::ChatPostMessage, text: "hi", conversation: foreign.external_id)

    assert_equal 1, result[:exit_code]
    assert_match(/No Teams conversation is named/, result[:stderr])
  end

  test "an Adaptive Card goes out as one; a clickable one, or Block Kit, is refused by name" do
    card = { "type" => "AdaptiveCard", "version" => "1.5", "body" => [ { "type" => "TextBlock", "text" => "Ready" } ] }
    stub_request(:post, @thread)
      .with(body: hash_including("attachments" => [ { "contentType" => "application/vnd.microsoft.card.adaptive", "content" => card } ]))
      .to_return(status: 201, body: { id: "1" }.to_json)

    assert_equal 0, run_tool(InternalTools::ChatPostMessage, text: "Ready", adaptive_card: card)[:exit_code]

    clicky = card.merge("actions" => [ { "type" => "Action.Submit", "title" => "Approve" } ])
    assert_match(/Action.Submit/, run_tool(InternalTools::ChatPostMessage, adaptive_card: clicky)[:stderr])
    assert_match(/`slack_blocks` is for Slack/,
                 run_tool(InternalTools::ChatPostMessage, slack_blocks: [ { "type" => "divider" } ])[:stderr])
  end

  test "a Teams throttle comes back as rate_limited with when to retry" do
    stub_request(:post, @thread).to_return(status: 429, headers: { "Retry-After" => "0" })

    result = run_tool(InternalTools::ChatPostMessage, text: "hi")

    assert_equal 1, result[:exit_code]
    assert_equal "rate_limited", JSON.parse(result[:stderr])["error"]
  end

  test "reading the Teams thread a run came from goes through Graph, oldest first" do
    base = "#{GRAPH}/teams/1b22f251-0000-4000-8000-000000000001/channels/19%3Aabc%40thread.tacv2/messages/1700000000001"
    stub_request(:get, base).to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
      id: "1700000000001", createdDateTime: "2026-10-06T10:00:00Z", from: { user: { displayName: "Olo" } },
      body: { contentType: "html", content: "<p>Can we ship &amp; tag?</p>" }
    }.to_json)
    stub_request(:get, "#{base}/replies?%24top=30").to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
      value: [
        { id: "3", createdDateTime: "2026-10-06T10:02:00Z", from: { application: { displayName: "Aixle Flow" } },
          body: { contentType: "text", content: "On it" } },
        { id: "2", createdDateTime: "2026-10-06T10:01:00Z", from: { user: { displayName: "Ana" } },
          body: { contentType: "html", content: "<at>Aixle Flow</at>&nbsp;deploy" }, attachments: [ { name: "notes.pdf" } ] }
      ]
    }.to_json)

    result = run_tool(InternalTools::ChatReadThread, {})

    messages = JSON.parse(result[:stdout])["messages"]
    assert_equal [ "Can we ship & tag?", "Aixle Flow deploy", "On it" ], messages.pluck("text")
    assert_equal [ false, false, true ], messages.pluck("bot")
    assert_equal [ "notes.pdf" ], messages.second["files"]
  end

  test "a Teams 1:1 thread cannot be read back, and says so" do
    direct = ChatConversation.record_teams!(integration: @teams, activity: teams_activity(conversation_type: "personal"))
    session = session_for(Chat::TeamsProvider.run_context(TriggerEvent.new(data: {
      "provider" => "teams", "integration_id" => @teams.id, "conversation" => { "id" => direct.external_id, "type" => "direct" },
      "message_id" => "9", "raw_text" => "make a report"
    })))

    result = JSON.parse(run_tool(InternalTools::ChatReadThread, {}, session: session)[:stdout])

    assert_equal [ "make a report" ], result["messages"].pluck("text")
    assert_match(/no access to the history of a 1:1 chat/, result["note"])
  end

  test "editing and deleting a Teams message address it in its thread" do
    edited = stub_request(:put, "#{@thread}/1700000000777").to_return(status: 200, body: "{}")
    deleted = stub_request(:delete, "#{@thread}/1700000000777").to_return(status: 200, body: "")

    assert_equal 0, run_tool(InternalTools::ChatUpdateMessage, message_id: "1700000000777", text: "50%")[:exit_code]
    assert_equal 0, run_tool(InternalTools::ChatDeleteMessage, message_id: "1700000000777")[:exit_code]

    assert_requested edited
    assert_requested deleted
  end

  test "in Slack the same tools answer in the Slack thread, Markdown as a markdown block" do
    stub_slack_client!
    slack = Integration.create!(provider: :slack, company: @company, connected_by: @user, name: "Acme", status: :active)
    slack.update!(credentials_data: { "bot_token" => "xoxb-1" })
    session = session_for("chat" => { "provider" => "slack", "conversation" => { "id" => "C1", "type" => "channel" },
                                      "thread_id" => "111.2", "integration_id" => slack.id })

    result = run_tool(InternalTools::ChatPostMessage, { text: "**Done**" }, session: session)

    assert_equal 0, result[:exit_code], result[:stderr]
    posted = fake_slack.last_posted_message
    assert_equal [ "C1", "111.2", "**Done**" ], posted.values_at(:channel, :thread_ts, :text)
    assert_equal [ { "type" => "markdown", "text" => "**Done**" } ], posted[:blocks]
    assert_equal "slack", JSON.parse(result[:stdout])["provider"]
    assert_match(/adaptive_card` is for Microsoft Teams/,
                 run_tool(InternalTools::ChatPostMessage, { adaptive_card: { "type" => "AdaptiveCard" } }, session: session)[:stderr])
  end

  test "with two messengers connected and no chat origin, the provider must be named" do
    Integration.create!(provider: :slack, company: @company, connected_by: @user, name: "Acme", status: :active)

    result = run_tool(InternalTools::ChatPostMessage, { text: "hi" }, session: session_for({}))

    assert_match(/Name the messenger: pass `provider` \(slack or teams\)/, result[:stderr])
  end

  test "the chat tools are offered wherever Slack or Teams is connected" do
    assert Tools::Context.for_project(@project).connected?(Chat::CAPABILITY)
    assert_includes Tool.active_integration_providers(@project), Chat::CAPABILITY

    @teams.update!(status: :inactive)
    assert_not Tools::Context.for_project(@project).connected?(Chat::CAPABILITY)
  end
end
