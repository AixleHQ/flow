# frozen_string_literal: true

require "test_helper"

class ChatConnectCodeTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
  end

  test "a code is shown once and stored only as its digest, for ten minutes" do
    freeze_time do
      record, code = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: "#deploys")

      assert_match(/\Aaixle-[0-9A-HJKMNP-TV-Z]{8}\z/, code)
      assert_equal ChatConnectCode.digest(code), record.code_digest
      assert_not_includes record.attributes.values.map(&:to_s), code
      assert_equal [ @project.company_id, 10.minutes.from_now ], [ record.company_id, record.expires_at ]
      assert_equal "pending", record.state
      travel 10.minutes
      assert_equal "expired", record.state
    end
  end

  test "the code is found in a message however it was typed, and nothing else passes for one" do
    assert_equal "aixle-7F3K9QXM", ChatConnectCode.extract("connect Aixle-7f3k9qxm please")
    assert_equal ChatConnectCode.digest("aixle-7F3K9QXM"), ChatConnectCode.digest("AIXLE-7f3k9qxm")
    assert_nil ChatConnectCode.extract("connect aixle-7F3K9QX")
    assert_nil ChatConnectCode.extract("connect aixle-ILOU0000"), "I, L, O and U are not in the alphabet"
  end

  test "a company holds at most ten unused codes at a time" do
    ChatConnectCode::MAX_OPEN_PER_COMPANY.times { ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: "#deploys") }

    error = assert_raises(ActiveRecord::RecordInvalid) { ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: "#deploys") }
    assert_match(/Too many unused codes/, error.message)

    travel(11.minutes) { assert ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "Sales / General").first.persisted? }
  end

  test "the digest needs the server's secret, not just the code" do
    assert_not_equal Digest::SHA256.hexdigest("aixle-7f3k9qxm"), ChatConnectCode.digest("aixle-7F3K9QXM")
  end

  test "a code knows its channel however it was typed, and a Teams channel only together with its team" do
    slack, = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: "  #Deploys ")
    deploys = ChatConversation.new(provider: "slack", kind: "channel", name: "deploys", external_id: "C1")
    assert_equal [ "Deploys", "#Deploys" ], [ slack.channel_name, slack.channel_label ]
    assert_nil slack.channel_mismatch(deploys)
    assert_equal "Posted in #random, but the code is for #Deploys", slack.channel_mismatch(deploys.dup.tap { |c| c.name = "random" })

    teams, = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "Sales/General")
    general = ChatConversation.new(provider: "teams", kind: "channel", name: "General", team_name: "Sales", external_id: "19:x")
    assert_nil teams.channel_mismatch(general)
    assert_match(%r{but the code is for Sales / General}, teams.channel_mismatch(general.dup.tap { |c| c.team_name = "Support" }))

    chat, = ChatConnectCode.issue!(project: @project, provider: "teams", user: @user, channel: "Launch crew")
    assert_nil chat.channel_mismatch(ChatConversation.new(provider: "teams", kind: "group", name: "launch crew", external_id: "19:g"))
    assert_equal "Name the team too for a Teams channel: Team / Channel", chat.channel_mismatch(general)
  end
end
