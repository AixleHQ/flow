# frozen_string_literal: true

require "test_helper"

# `@bot connect <code>` connecting the channel the code names, through the same
# path a real mention takes (Webhooks::ProcessEventJob → Chat::WorkspaceRouter).
class Chat::ChannelConnectTest < ActiveJob::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @company.update!(name: "Acme")
    @project = create(:project, owner: @user, company: @company, name: "Payments")
    @workflow = create(:workflow, scope: @project, name: "Deploy")
    create(:step, workflow: @workflow, allow_non_interactive: true)
    @slack = Integration.create!(provider: :slack, company: @company, project: nil, connected_by: @user,
                                 name: "Acme", status: :active, settings: { "team_id" => "T1" })
    @slack.update!(credentials_data: { "bot_token" => "xoxb-1", "bot_user_id" => "U0BOT" })
    @endpoint = create(:webhook_endpoint, provider: :slack, project: nil, company: @company,
                                          config: { "integration_id" => @slack.id })
    stub_slack_client!.channel_names = { "C0NEW00001" => "deploys", "C0OTHER001" => "random" }
    fake_slack.user_names = { "U0POSTER" => "olo" }
  end

  def slack_mention(text, channel: "C0NEW00001", key: SecureRandom.hex)
    received = ReceivedWebhook.create!(webhook_endpoint: @endpoint, idempotency_key: key, event_type: "slack", raw_payload: {
      "type" => "event_callback", "event_id" => key, "team_id" => "T1",
      "event" => { "type" => "app_mention", "channel" => channel, "user" => "U0POSTER", "text" => "<@U0BOT> #{text}",
                   "ts" => "100.1" }
    })
    Webhooks::ProcessEventJob.perform_now(received.id)
  end

  def code_for(channel = "#deploys", **attrs)
    ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: channel, **attrs)
  end

  test "a code posted in the Slack channel it names connects it, and the bot says so naming only the company" do
    trigger = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, name: "Deploy",
                                       enabled: false, chat_channel: nil)
    code_record, code = code_for("deploys", trigger_binding: trigger)

    slack_mention("connect #{code.downcase}")

    connection = ChatChannelConnection.sole
    assert_equal [ @company, @user, "U0POSTER", "olo" ],
                 [ connection.company, connection.requested_by, connection.posted_by_external_id, connection.posted_by_name ]
    assert_equal [ "slack", "C0NEW00001", "deploys" ],
                 [ connection.chat_conversation.provider, connection.chat_conversation.external_id, connection.chat_conversation.name ]
    assert_equal "redeemed", code_record.reload.state
    assert_equal connection.chat_conversation, trigger.reload.chat_conversation
    assert_not trigger.enabled, "switching the trigger on stays its owner's call"

    reply = fake_slack.last_posted_message
    assert_equal [ "C0NEW00001", "100.1" ], reply.values_at(:channel, :thread_ts)
    assert_equal "This channel is now connected to *Acme*.\na mention of <@U0BOT> here starts one of *Acme*'s workflows.",
                 reply[:text]
    assert_not_includes reply[:text], @user.name
    assert_not_includes reply[:text], "Payments"
    assert_equal reply[:ts], connection.confirmation_message_id
    assert_equal 0, TriggerDispatch.count
  end

  test "the confirmation names the command a trigger answers, a channel for posting says so, and a second code adds nothing" do
    trigger = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, enabled: false,
                                       chat_channel: nil, filter_predicate: { "text" => { "op" => "starts_with", "value" => "deploy" } })
    _record, with_trigger = code_for(trigger_binding: trigger)
    slack_mention("connect #{with_trigger}")
    assert_includes fake_slack.last_posted_message[:text], "<@U0BOT> deploy here starts one of *Acme*'s workflows."

    _record, posting = code_for("#random")
    slack_mention("connect #{posting}", channel: "C0OTHER001")
    assert_includes fake_slack.last_posted_message[:text], "*Acme*'s workflows can post here."

    _record, again = code_for("#random")
    slack_mention("connect #{again}", channel: "C0OTHER001")
    assert_includes fake_slack.last_posted_message[:text], "This channel was already connected to *Acme*."
    assert_equal 2, ChatChannelConnection.count
  end

  test "a code posted anywhere but its own channel connects nothing, and stays good for its own" do
    record, code = code_for("#deploys")

    slack_mention("connect #{code}", channel: "C0OTHER001")

    assert_equal 0, ChatChannelConnection.count
    assert_equal "Posted in #random, but the code is for #deploys", record.reload.failure_reason
    assert_equal [ [ "C0OTHER001", "U0POSTER", Chat::ChannelConnect::UNUSABLE ] ],
                 fake_slack.ephemeral_messages.map { |m| m.values_at(:channel, :user, :text) }

    slack_mention("connect #{code}")
    assert_equal "C0NEW00001", ChatChannelConnection.sole.chat_conversation.external_id
  end

  test "every refusal is shown only to whoever posted it, and its requester sees why on the code" do
    _record, used = code_for
    slack_mention("connect #{used}")
    public_before = fake_slack.posted_messages.size
    expired, expired_code = code_for("#random")
    teams, teams_code = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "Sales / General")
    stranger = create(:user, :with_company)
    elsewhere = create(:project, company: stranger.companies.first, owner: stranger)
    foreign, foreign_code = ChatConnectCode.issue!(project: elsewhere, provider: "slack", user: stranger, channel: "#random")

    travel_to(11.minutes.from_now) { slack_mention("connect #{expired_code}", channel: "C0OTHER001") }
    slack_mention("connect #{used}", channel: "C0OTHER001")
    slack_mention("connect #{teams_code}", channel: "C0OTHER001")
    slack_mention("connect #{foreign_code}", channel: "C0OTHER001")
    slack_mention("connect aixle-ZZZZZZZZ", channel: "C0OTHER001")

    assert_equal public_before, fake_slack.posted_messages.size, "nothing is said to the whole channel"
    assert_equal [ Chat::ChannelConnect::UNUSABLE ] * 5, fake_slack.ephemeral_messages.pluck(:text)
    assert_equal 1, ChatChannelConnection.count
    assert_equal [ "Expired", "Posted in Slack, but the code is for Microsoft Teams",
                   "Posted in a workspace this company has not connected" ],
                 [ expired.reload.failure_reason, teams.reload.failure_reason, foreign.reload.failure_reason ]
  end

  test "a workspace whose install may not read channel names cannot be checked, and says why" do
    fake_slack.conversation_info_error = "missing_scope"
    record, code = code_for

    slack_mention("connect #{code}")

    assert_equal 0, ChatChannelConnection.count
    assert_match(/did not say what this channel is called — reinstall the app/, record.reload.failure_reason)
  end

  test "the bare word asks for a code privately, and a request that only starts with it reaches the triggers" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_channel: "C0NEW00001",
                             filter_predicate: { "text" => { "op" => "starts_with", "value" => "connect the repo" } })
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    slack_mention("connect")
    slack_mention("connect the repo to staging")

    assert_match(/request a code in Aixle \(Integrations → Slack → Connect a channel/, fake_slack.ephemeral_messages.sole[:text])
    assert_equal 1, TriggerDispatch.count
  end

  test "a Teams channel is named with its team; a code in a 1:1 chat is refused" do
    with_teams_enabled
    stub_teams_token!
    teams = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    endpoint = create(:webhook_endpoint, slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}", provider: :teams,
                                         verification_strategy: :none, secret: nil, company: @company,
                                         config: { "integration_id" => teams.id })
    no_team, no_team_code = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "Onboarding")
    _record, code = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "sales / onboarding")
    thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
    refused = stub_request(:post, thread).with(body: /not valid here/).to_return(status: 201, body: { id: "7" }.to_json)
    confirmed = stub_request(:post, thread).with(body: /now connected to \*\*Acme\*\*/).to_return(status: 201, body: { id: "9" }.to_json)
    direct = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/a:1personal/activities")
             .with(body: /not in a direct chat/).to_return(status: 201, body: { id: "8" }.to_json)

    [ teams_activity(text: "connect #{code}", conversation_type: "personal", mention: false),
      teams_activity(text: "connect #{no_team_code}"), teams_activity(text: "connect #{code}") ].each do |activity|
      ChatConversation.record_teams!(integration: teams, activity: activity)
      received = ReceivedWebhook.create!(webhook_endpoint: endpoint, idempotency_key: SecureRandom.hex, event_type: "teams",
                                         raw_payload: activity)
      Webhooks::ProcessEventJob.perform_now(received.id)
    end

    assert_requested direct
    assert_requested refused
    assert_requested confirmed
    assert_equal "Name the team too for a Teams channel: Team / Channel", no_team.reload.failure_reason
    connection = ChatChannelConnection.sole
    assert_equal [ "19:abc@thread.tacv2", "9" ], [ connection.chat_conversation.external_id, connection.confirmation_message_id ]
  end
end
