# frozen_string_literal: true

require "test_helper"

class TriggerBindingTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
  end

  test "valid binding for a project-accessible workflow" do
    binding = TriggerBinding.new(
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message", filter_predicate: { "provider" => "slack" },
      chat_conversation: connect_chat_channel(company: @company)
    )
    assert binding.valid?, binding.errors.full_messages.to_sentence
  end

  test "invalid when workflow is not accessible from the project" do
    other_company = create(:company)
    other_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    foreign_workflow = create(:workflow, scope: other_project)

    binding = TriggerBinding.new(
      project: @project, workflow: foreign_workflow, created_by: @user,
      event_type: "chat.message"
    )

    assert_not binding.valid?
    assert_includes binding.errors[:workflow], "must be accessible from this project"
  end

  test "requires an event_type" do
    binding = TriggerBinding.new(project: @project, workflow: @workflow, event_type: nil)
    assert_not binding.valid?
    assert_includes binding.errors[:event_type], "can't be blank"
  end

  test "matches? does JSONB-style containment of the predicate within event data" do
    binding = build(:trigger_binding, event_type: "webhook.received", filter_predicate: { "channel" => "C1" })

    assert binding.matches?("channel" => "C1", "user" => "U9")
    assert_not binding.matches?("channel" => "C2")
    assert_not binding.matches?("user" => "U9")
  end

  test "empty predicate matches any event of the type" do
    binding = build(:trigger_binding, event_type: "webhook.received", filter_predicate: {})
    assert binding.matches?("anything" => "goes")
  end

  test "subject_policy defaults to none" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")
    assert_equal "none", binding.subject_policy
  end

  test "create_task subject_policy requires a subject_column" do
    binding = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message", subject_policy: :create_task, subject_column: nil)

    assert_not binding.valid?
    assert_includes binding.errors[:subject_column], "is required when subject_policy is create_task"
  end

  test "a subject_column on another project's board is rejected" do
    other_project = create(:project, owner: @user, company: @company)
    foreign_column = create(:board_column, board: create(:board, project: other_project))
    own_column = create(:board_column, board: create(:board, project: @project))

    foreign = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message", subject_policy: :create_task, subject_column: foreign_column)
    own = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message", subject_policy: :create_task, subject_column: own_column)

    assert_not foreign.valid?
    assert_match(/subject_column_id must belong to this project/, foreign.errors[:subject_column].join)
    assert own.valid?
  end

  test "schedule binding requires a cron in schedule_config" do
    binding = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "schedule.fired", schedule_config: {})

    assert_not binding.valid?
    assert_includes binding.errors[:schedule_config], "must include a cron expression"
  end

  test "invalid when a workflow step requires user interaction (no auto-run)" do
    wf = create(:workflow, scope: @project)
    wf.steps.create!(name: "Manual step", position: 1, allow_non_interactive: false)

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user, event_type: "chat.message",
                                 filter_predicate: { "provider" => "slack" })

    assert_not binding.valid?
    assert_includes binding.errors[:workflow].join, "Manual step"
  end

  test "valid when every workflow step allows auto-run" do
    wf = create(:workflow, scope: @project)
    wf.steps.create!(name: "Auto step", position: 1, allow_non_interactive: true)

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user, event_type: "chat.message",
                                 filter_predicate: { "provider" => "slack" }, chat_conversation: connect_chat_channel(company: @company))

    assert binding.valid?, binding.errors.full_messages.to_sentence
  end

  test "a disabled binding skips the auto-run validation" do
    wf = create(:workflow, scope: @project)
    wf.steps.create!(name: "Manual step", position: 1, allow_non_interactive: false)

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user,
      event_type: "chat.message", filter_predicate: { "provider" => "slack" }, enabled: false)

    assert binding.valid?
  end

  test "for_event scopes by project, event_type and enabled" do
    match = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "other.type")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message", enabled: false)

    event = create(:trigger_event, event_type: "chat.message", project: @project, source: "slack:slack-team-T1",
                                   data: slack_message)

    assert_equal [ match.id ], TriggerBinding.for_event(event).pluck(:id)
  end

  test "a chat message matches the chat triggers of its own messenger" do
    slack = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                             chat_provider: "teams")

    event = create(:trigger_event, event_type: "chat.message", source: "slack:slack-team-T1",
                                   data: slack_message, project: @project)

    assert_equal [ slack.id ], TriggerBinding.for_event(event).select { |b| b.matches?(event.data) }.map(&:id)
  end

  test "a chat message from anything but its provider's receiver matches no trigger" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                             filter_predicate: { "provider" => "slack" })

    event = create(:trigger_event, event_type: "chat.message", source: "generic:wh-1",
                                   data: { "provider" => "slack" }, project: @project)

    assert_empty TriggerBinding.for_event(event)
  end

  test "a chat trigger matches only the messenger it names" do
    teams = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                     event_type: "chat.message", filter_predicate: { "provider" => "teams" })

    assert teams.matches?({ "provider" => "teams", "text" => "deploy" }), "the channel is for_event's to check"

    assert_not teams.matches?({ "provider" => "slack", "text" => "deploy" })
  end

  test "a chat trigger must name a messenger it knows" do
    binding = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                                    chat_provider: nil, enabled: false)

    assert_not binding.valid?
    binding.filter_predicate = { "provider" => "irc" }
    assert_not binding.valid?
    binding.filter_predicate = { "provider" => "teams" }
    assert binding.valid?
  end

  test "replacing a chat trigger's conditions keeps its messenger" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, enabled: false,
                                       event_type: "chat.message", filter_predicate: { "provider" => "teams" })

    binding.update!(filter_predicate: { "text" => "deploy" })
    assert_equal({ "text" => "deploy", "provider" => "teams", "channel" => ChatChannelTestHelper::TEAMS_CHANNEL },
                 binding.reload.filter_predicate)

    binding.assign_chat_provider("slack")
    binding.save!
    assert_equal "slack", binding.reload.chat_provider
  end

  test "a Slack trigger moved to Teams keeps its conditions but not its Slack channel" do
    create(:integration, provider: :teams, status: :active, company: @project.company, project: nil)
    legacy = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                                      filter_predicate: { "channel" => "C1", "text" => "deploy" })

    legacy.assign_chat_provider("teams")
    error = assert_raises(ActiveRecord::RecordInvalid) { legacy.save_checking_chat! }
    assert_match(/Chat channel is required/, error.message)

    legacy.enabled = false
    legacy.save_checking_chat!

    assert_equal [ "chat.message", "teams", nil ], [ legacy.reload.event_type, legacy.chat_provider, legacy.chat_conversation ]
    assert_equal({ "text" => "deploy", "provider" => "teams" }, legacy.filter_predicate)
  end

  test "moving an enabled chat trigger to a messenger the company has not connected is refused" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")

    binding.filter_predicate = { "provider" => "teams" }

    assert_raises(ActiveRecord::RecordInvalid) { binding.save_checking_chat! }
    assert_equal "slack", binding.reload.chat_provider
  end

  test "only a chat trigger can follow its run with a status card" do
    webhook = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                      event_type: "webhook.received", status_reporting: "lifecycle")

    assert_not webhook.valid?
    assert_includes webhook.errors[:status_reporting], "lifecycle is for chat triggers"
  end

  test "accepts an empty predicate and a scalar or known operator condition" do
    empty = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, filter_predicate: {})
    scalar = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "webhook.received", filter_predicate: { "branch" => "main" })
    operator = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      filter_predicate: { "text" => { "op" => "contains", "value" => "ship" } })
    present = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      filter_predicate: { "text" => { "op" => "present" } })

    assert empty.valid?
    assert scalar.valid?
    assert operator.valid?
    assert present.valid?
  end

  test "rejects a slack text command of help and allows a word that only contains it" do
    help = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message",
      filter_predicate: { "text" => { "op" => "eq", "value" => "help" } })
    slashed = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message",
      filter_predicate: { "text" => { "op" => "contains", "value" => "/HELP" } })
    helpful = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message",
      filter_predicate: { "text" => { "op" => "contains", "value" => "helpful" } })
    webhook = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "webhook.received",
      filter_predicate: { "text" => "help" })

    assert_not help.valid?
    assert_match(/can't use help/, help.errors[:filter_predicate].join)
    assert_not slashed.valid?
    assert helpful.valid?
    assert webhook.valid?
  end

  test "a slack binding matches its text condition without regard to case; other kinds keep case" do
    slack = build(:trigger_binding, event_type: "chat.message",
      filter_predicate: { "text" => { "op" => "starts_with", "value" => "deploy" } })
    webhook = build(:trigger_binding, event_type: "webhook.received",
      filter_predicate: { "text" => { "op" => "starts_with", "value" => "deploy" } })

    assert slack.matches?("provider" => "slack", "text" => "Deploy staging")
    assert_not webhook.matches?("text" => "Deploy staging")
  end

  # A Slack message through the company's install, from the channel the
  # factory's chat triggers listen in.
  def slack_message(data = {})
    { "provider" => "slack", "channel" => ChatChannelTestHelper::SLACK_CHANNEL,
      "integration_id" => Integration.where(company: @company, provider: :slack).pick(:id) }.merge(data)
  end

  def slack_binding(**attrs)
    build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message", **attrs)
  end

  test "save_checking_chat! refuses to create or switch on a slack trigger until the company connects Slack" do
    error = assert_raises(ActiveRecord::RecordInvalid) { slack_binding.save_checking_chat! }
    assert_includes error.record.errors.full_messages, TriggerBinding.chat_not_connected("Slack")
    assert_equal 0, TriggerBinding.count

    off = slack_binding(enabled: false)
    off.save_checking_chat!
    assert off.persisted?, "a disabled slack trigger hears nothing, so it can wait for Slack"

    off.enabled = true
    assert_raises(ActiveRecord::RecordInvalid) { off.save_checking_chat! }
    assert_equal false, off.reload.enabled # rubocop:disable Minitest/RefuteFalse

    create(:integration, provider: :slack, status: :active, company: @company, project: nil)
    off.enabled = true
    off.save_checking_chat!
    assert off.reload.enabled
  end

  test "save_checking_chat! still saves other edits of a slack trigger whose workspace went away" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "chat.message", name: "before")

    binding.name = "after"
    binding.save_checking_chat!

    assert_equal "after", binding.reload.name
  end

  test "save_checking_chat! reports the binding's other errors alongside the missing connection" do
    create(:step, workflow: @workflow, name: "Review copy", allow_non_interactive: false)

    error = assert_raises(ActiveRecord::RecordInvalid) { slack_binding.save_checking_chat! }

    messages = error.record.errors.full_messages.join(" ")
    assert_match(/can't run unattended/, messages)
    assert_includes messages, TriggerBinding.chat_not_connected("Slack")
  end

  def schedule_binding(enabled:)
    TriggerBinding.create!(project: @project, workflow: @workflow, created_by: @user, event_type: "schedule.fired",
                           enabled: enabled, schedule_config: { "cron" => "0 9 * * *", "timezone" => "UTC" })
  end

  test "a schedule created disabled never reaches Temporal, since it has no schedule yet" do
    TemporalService.stubs(:enabled?).returns(true)
    ScheduleReconciler.expects(:reconcile).never

    schedule_binding(enabled: false)
  end

  test "a schedule is reconciled when created enabled and again when switched on" do
    TemporalService.stubs(:enabled?).returns(true)
    ScheduleReconciler.expects(:reconcile).twice

    schedule_binding(enabled: true)
    schedule_binding(enabled: false).update!(name: "renamed")
  end

  test "a chat message reaches only the triggers bound to its channel, and only where the channel is connected" do
    here = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_channel: "C0HERE0001")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_channel: "C0ELSEWHR1")
    event = create(:trigger_event, event_type: "chat.message", source: "slack:slack-team-T1", company: @company,
                                   data: slack_message("channel" => "C0HERE0001"))

    assert_equal [ here.id ], TriggerBinding.for_event(event).pluck(:id)

    ChatChannelConnection.where(company: @company, chat_conversation: here.chat_conversation).delete_all
    assert_empty TriggerBinding.for_event(event), "a channel no longer connected starts nothing"
  end

  test "a chat trigger's conditions can't name where a message comes from" do
    binding = slack_binding(enabled: false)

    %w[channel conversation.id conversation.type workspace.id team integration_id subject service_url].each do |key|
      binding.filter_predicate = { "provider" => "slack", key => "x" }
      assert_not binding.valid?, key
      assert_match(/can't name where a message comes from \(#{Regexp.escape(key)}\)/, binding.errors[:filter_predicate].join)
    end

    binding.filter_predicate = { "provider" => "slack", "user" => "U1", "text" => { "op" => "contains", "value" => "go" } }
    assert binding.valid?, binding.errors.full_messages.to_sentence
  end

  test "a chat trigger is switched on only in a channel of its own messenger connected to its company" do
    binding = slack_binding(chat_channel: nil)
    assert_not binding.valid?
    assert_includes binding.errors.full_messages, "Chat channel is required — connect a channel to this company and choose it"

    binding.chat_conversation = connect_chat_channel(company: create(:company), external_id: "C0FOREIGN1")
    assert_not binding.valid?
    assert_includes binding.errors.full_messages, "Chat channel is not connected to this company"

    binding.chat_conversation = connect_chat_channel(company: @company, provider: "teams")
    assert_not binding.valid?
    assert_includes binding.errors.full_messages, "Chat channel belongs to another messenger"

    binding.chat_conversation = connect_chat_channel(company: @company, external_id: "C0OWN00001")
    assert binding.valid?, binding.errors.full_messages.to_sentence
    assert binding.chat_channel_usable?
  end

  test "the trigger's channel is kept beside it in its conditions, for the release that still matches on that" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, chat_channel: "C0FIRST001")
    assert_equal({ "provider" => "slack", "channel" => "C0FIRST001" }, binding.filter_predicate)

    binding.update!(chat_conversation: connect_chat_channel(company: @company, external_id: "C0SECOND01"))
    assert_equal({ "provider" => "slack", "channel" => "C0SECOND01" }, binding.reload.filter_predicate)
  end

  test "releasing chat channels switches the triggers off and clears their channel, nothing else" do
    chat = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user)
    schedule = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, enabled: false,
                                        event_type: "schedule.fired", schedule_config: { "cron" => "0 9 * * *" })

    TriggerBinding.release_chat_channels!(TriggerBinding.where(project: @project))

    chat.reload
    assert_equal [ false, nil, { "provider" => "slack" } ], [ chat.enabled, chat.chat_conversation, chat.filter_predicate ]
    assert_equal({ "cron" => "0 9 * * *" }, schedule.reload.schedule_config)
  end
end
