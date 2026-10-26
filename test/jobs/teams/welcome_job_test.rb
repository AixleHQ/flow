# frozen_string_literal: true

require "test_helper"

class Teams::WelcomeJobTest < ActiveJob::TestCase
  setup do
    with_teams_enabled
    stub_teams_token!
    user = create(:user, :with_company)
    @integration = Integration.create!(provider: :teams, company: user.companies.first, connected_by: user,
                                       name: "Contoso", status: :active)
    @channel = ChatConversation.record_teams!(integration: @integration, activity: teams_activity)
    @team = "#{TEAMS_SERVICE_URL}v3/teams/19%3Ateam%40thread.tacv2"
    @channel_posts = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2/activities"
  end

  def stub_team!
    stub_request(:get, @team)
      .to_return(status: 200, body: { aadGroupId: "1b22f251-0000-4000-8000-000000000001", name: "Sales", memberCount: 12 }.to_json)
    stub_request(:get, "#{@team}/conversations").to_return(status: 200, body: { conversations: [] }.to_json)
  end

  def bot_disabled
    { status: 403, body: { error: { code: "BotDisabledByAdmin", message: "The tenant admin disabled this bot" } }.to_json }
  end

  test "a 1:1 chat is welcomed once" do
    direct = ChatConversation.record_teams!(integration: @integration, activity: teams_activity(conversation_type: "personal"))
    welcome = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/a%3A1personal/activities")
              .with(body: hash_including("text" => /Send me a request/)).to_return(status: 201, body: { id: "1" }.to_json)

    2.times { Teams::WelcomeJob.perform_now(direct.id) }

    assert_requested welcome, times: 1
    assert_not_nil direct.reload.welcomed_at
  end

  test "a conversation that refuses the bot is not welcomed and not tried again" do
    stub_request(:get, @team).to_return(bot_disabled)

    assert_no_enqueued_jobs(only: Teams::WelcomeJob) { Teams::WelcomeJob.perform_now(@channel.id) }
    assert_not_requested :post, @channel_posts

    stub_team!
    refused = stub_request(:post, @channel_posts).to_return(bot_disabled)

    assert_no_enqueued_jobs(only: Teams::WelcomeJob) { Teams::WelcomeJob.perform_now(@channel.id) }
    assert_requested refused
    assert_equal "1b22f251-0000-4000-8000-000000000001", @channel.reload.team_aad_group_id
    assert_nil @channel.welcomed_at
  end

  test "a throttle or an outage is tried again later" do
    stub_request(:get, @team).to_timeout

    assert_enqueued_with(job: Teams::WelcomeJob, args: [ @channel.id ]) { Teams::WelcomeJob.perform_now(@channel.id) }

    stub_team!
    stub_request(:post, @channel_posts).to_return(status: 429)

    assert_enqueued_with(job: Teams::WelcomeJob, args: [ @channel.id ]) { Teams::WelcomeJob.perform_now(@channel.id) }
    assert_nil @channel.reload.welcomed_at
  end
end
