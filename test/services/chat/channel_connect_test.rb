# frozen_string_literal: true

require "test_helper"

# `@bot connect <code>` connecting the channel it was posted in, through the same
# path a real mention takes (Webhooks::ProcessEventJob → TriggerEngine.dispatch).
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
    stub_slack_client!.channel_names = { "C0NEW00001" => "deploys" }
  end

  def slack_mention(text, channel: "C0NEW00001", key: SecureRandom.hex)
    received = ReceivedWebhook.create!(webhook_endpoint: @endpoint, idempotency_key: key, event_type: "slack", raw_payload: {
      "type" => "event_callback", "event_id" => key, "team_id" => "T1",
      "event" => { "type" => "app_mention", "channel" => channel, "user" => "U0POSTER", "text" => "<@U0BOT> #{text}",
                   "ts" => "100.1" }
    })
    Webhooks::ProcessEventJob.perform_now(received.id)
  end

  test "a code posted in a Slack channel connects it to the company that asked, and says so in the thread" do
    trigger = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, name: "Deploy",
                                       enabled: false, chat_channel: nil)
    code_record, code = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, trigger_binding: trigger)

    slack_mention("connect #{code.downcase}")

    connection = ChatChannelConnection.sole
    assert_equal [ @company, @user, "U0POSTER" ], [ connection.company, connection.requested_by, connection.posted_by_external_id ]
    assert_equal [ "slack", "C0NEW00001", "deploys", @slack ],
                 [ connection.chat_conversation.provider, connection.chat_conversation.external_id,
                   connection.chat_conversation.name, connection.chat_conversation.integration ]
    assert_equal "redeemed", code_record.reload.state
    assert_equal connection.chat_conversation, trigger.reload.chat_conversation
    assert_not trigger.enabled, "switching the trigger on stays its owner's call"

    reply = fake_slack.last_posted_message
    assert_equal [ "C0NEW00001", "100.1" ], reply.values_at(:channel, :thread_ts)
    assert_includes reply[:text], "This channel is now connected to *Acme* (#{@user.name} in Aixle, posted by <@U0POSTER>)."
    assert_includes reply[:text], "Trigger *Deploy* in project *Payments* listens to mentions of <@U0BOT> here."
    assert_equal reply[:ts], connection.confirmation_message_id
    assert_equal 0, TriggerDispatch.count
  end

  test "a code asked for a channel to post to says so, and a second code for the same channel adds nothing" do
    _record, first = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user)
    _record, second = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user)

    slack_mention("connect #{first}")
    assert_includes fake_slack.last_posted_message[:text], "*Acme*'s workflows can post here."

    slack_mention("connect #{second}")
    assert_includes fake_slack.last_posted_message[:text], "This channel was already connected to *Acme*."
    assert_equal 1, ChatChannelConnection.count
  end

  test "a code that cannot be used gets one answer for every reason, and its requester sees which" do
    _record, used = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user)
    slack_mention("connect #{used}")
    expired, expired_code = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user)
    teams, teams_code = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user)
    stranger = create(:user, :with_company)
    elsewhere = create(:project, company: stranger.companies.first, owner: stranger)
    foreign, foreign_code = ChatConnectCode.issue!(project: elsewhere, provider: "slack", user: stranger)

    travel_to(11.minutes.from_now) { slack_mention("connect #{expired_code}", channel: "C0OTHER001") }
    slack_mention("connect #{used}", channel: "C0OTHER001")
    slack_mention("connect #{teams_code}", channel: "C0OTHER001")
    slack_mention("connect #{foreign_code}", channel: "C0OTHER001")
    slack_mention("connect aixle-ZZZZZZZZ", channel: "C0OTHER001")

    replies = fake_slack.posted_messages.select { |m| m[:channel] == "C0OTHER001" }.pluck(:text)
    assert_equal [ Chat::ChannelConnect::UNUSABLE ] * 5, replies
    assert_equal 1, ChatChannelConnection.count
    assert_equal [ "Expired", "Posted in Slack, but the code is for Microsoft Teams",
                   "Posted in a workspace this company has not connected" ],
                 [ expired.reload.failure_reason, teams.reload.failure_reason, foreign.reload.failure_reason ]
  end

  test "the bare word asks for a code, and a request that only starts with it reaches the triggers" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_channel: "C0NEW00001",
                             filter_predicate: { "text" => { "op" => "starts_with", "value" => "connect the repo" } })
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    slack_mention("connect")
    slack_mention("connect the repo to staging")

    assert_match(/request a code in Aixle \(Integrations → Slack → Connect a channel/, fake_slack.posted_messages.first[:text])
    assert_equal 1, TriggerDispatch.count
  end

  test "a code posted in Teams connects the channel, and one in a 1:1 chat is refused" do
    with_teams_enabled
    stub_teams_token!
    teams = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    endpoint = create(:webhook_endpoint, slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}", provider: :teams,
                                         verification_strategy: :none, secret: nil, company: @company,
                                         config: { "integration_id" => teams.id })
    _record, code = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user)
    thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
    confirmed = stub_request(:post, thread).with(body: /now connected to \*\*Acme\*\*/).to_return(status: 201, body: { id: "9" }.to_json)
    direct = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/a:1personal/activities")
             .with(body: /not in a direct chat/).to_return(status: 201, body: { id: "8" }.to_json)

    [ teams_activity(text: "connect #{code}", conversation_type: "personal", mention: false),
      teams_activity(text: "connect #{code}") ].each do |activity|
      ChatConversation.record_teams!(integration: teams, activity: activity)
      received = ReceivedWebhook.create!(webhook_endpoint: endpoint, idempotency_key: SecureRandom.hex, event_type: "teams",
                                         raw_payload: activity)
      Webhooks::ProcessEventJob.perform_now(received.id)
    end

    assert_requested direct
    assert_requested confirmed
    connection = ChatChannelConnection.sole
    assert_equal [ "19:abc@thread.tacv2", "9" ], [ connection.chat_conversation.external_id, connection.confirmation_message_id ]
  end
end
