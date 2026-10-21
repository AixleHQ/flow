# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261022100100_connect_existing_chat_channels")

class ConnectExistingChatChannelsTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project, name: "Report")
    @slack = Integration.create!(provider: :slack, company: @company, project: nil, connected_by: @user, name: "Acme",
                                 status: :active, settings: { "team_id" => "T1" })
  end

  def migrate
    migration = ConnectExistingChatChannels.new
    migration.suppress_messages { migration.up }
  end

  # A chat trigger as the previous release stored it: its place inside its conditions.
  def legacy_trigger(filter, **attrs)
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, enabled: false,
                                       chat_channel: nil, **attrs)
    binding.update_columns(filter_predicate: filter, enabled: attrs.fetch(:enabled, true))
    binding
  end

  def fired(binding, channel, times)
    times.times do
      event = create(:trigger_event, event_type: "chat.message", company: @company, source: "slack:slack-team-T1",
                                     data: { "provider" => "slack", "integration_id" => @slack.id, "channel" => channel })
      TriggerDispatch.create!(trigger_event: event, trigger_binding: binding, dedup_key: SecureRandom.hex, status: "started")
    end
  end

  def connected?(external_id)
    ChatChannelConnection.joins(:chat_conversation)
                         .exists?(company: @company, chat_conversations: { external_id: external_id, integration_id: @slack.id })
  end

  test "every channel already in use is connected to its company, and each chat trigger listens in exactly one" do
    named = legacy_trigger({ "provider" => "slack", "channel" => "C0NAMED001", "text" => "go" })
    anywhere = legacy_trigger({ "provider" => "slack", "text" => { "op" => "contains", "value" => "report" } }, name: nil)
    fired(anywhere, "C0BUSY0001", 3)
    fired(anywhere, "C0QUIET001", 1)
    direct = legacy_trigger({ "provider" => "slack", "conversation.type" => "direct" })
    create(:step, workflow: @workflow, instructions: "Post the digest to C0DIGEST01 every CHECKLIST morning.")
    teams = Integration.create!(provider: :teams, company: @company, name: "Contoso", status: :active)
    teams_channel = teams.chat_conversations.create!(provider: "teams", external_id: "19:a@thread.tacv2", kind: "channel")
    teams.chat_conversations.create!(provider: "teams", external_id: "a:1personal", kind: "direct")

    migrate

    assert(%w[C0NAMED001 C0BUSY0001 C0QUIET001 C0DIGEST01].all? { |id| connected?(id) })
    assert_not ChatConversation.exists?(external_id: "CHECKLIST")
    assert_equal [ teams_channel.id ], ChatChannelConnection.where(company: @company)
                                                            .joins(:chat_conversation).where(chat_conversations: { provider: "teams" })
                                                            .pluck(:chat_conversation_id)

    assert_equal [ "C0NAMED001", true, { "provider" => "slack", "text" => "go", "channel" => "C0NAMED001" } ],
                 [ named.reload.chat_conversation.external_id, named.enabled, named.filter_predicate ]

    copy = TriggerBinding.where(workflow: @workflow).where.not(id: [ named.id, anywhere.id, direct.id ]).sole
    assert_equal [ "C0BUSY0001", true ], [ anywhere.reload.chat_conversation.external_id, anywhere.enabled ]
    assert_equal [ "C0QUIET001", true, "Report (2)" ], [ copy.chat_conversation.external_id, copy.enabled, copy.name ]
    assert_equal anywhere.filter_predicate.except("channel"), copy.filter_predicate.except("channel")
    assert_equal 4, TriggerDispatch.where(trigger_binding: anywhere).count, "the original keeps its history"

    assert_equal [ false, nil, { "provider" => "slack" } ], [ direct.reload.enabled, direct.chat_conversation, direct.filter_predicate ]
  end

  test "running it again changes nothing" do
    anywhere = legacy_trigger({ "provider" => "slack" })
    fired(anywhere, "C0BUSY0001", 2)
    fired(anywhere, "C0QUIET001", 1)
    migrate

    assert_no_difference -> { TriggerBinding.count } => 0, -> { ChatChannelConnection.count } => 0 do
      migrate
    end
  end
end
