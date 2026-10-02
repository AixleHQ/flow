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
      event_type: "slack.message"
    )
    assert binding.valid?
  end

  test "invalid when workflow is not accessible from the project" do
    other_company = create(:company)
    other_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    foreign_workflow = create(:workflow, scope: other_project)

    binding = TriggerBinding.new(
      project: @project, workflow: foreign_workflow, created_by: @user,
      event_type: "slack.message"
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
    binding = build(:trigger_binding, filter_predicate: { "channel" => "C1" })

    assert binding.matches?("channel" => "C1", "user" => "U9")
    assert_not binding.matches?("channel" => "C2")
    assert_not binding.matches?("user" => "U9")
  end

  test "empty predicate matches any event of the type" do
    binding = build(:trigger_binding, filter_predicate: {})
    assert binding.matches?("anything" => "goes")
  end

  test "subject_policy defaults to none" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    assert_equal "none", binding.subject_policy
  end

  test "create_task subject_policy requires a subject_column" do
    binding = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :create_task, subject_column: nil)

    assert_not binding.valid?
    assert_includes binding.errors[:subject_column], "is required when subject_policy is create_task"
  end

  test "a subject_column on another project's board is rejected" do
    other_project = create(:project, owner: @user, company: @company)
    foreign_column = create(:board_column, board: create(:board, project: other_project))
    own_column = create(:board_column, board: create(:board, project: @project))

    foreign = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :create_task, subject_column: foreign_column)
    own = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :create_task, subject_column: own_column)

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

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user, event_type: "slack.message")

    assert_not binding.valid?
    assert_includes binding.errors[:workflow].join, "Manual step"
  end

  test "valid when every workflow step allows auto-run" do
    wf = create(:workflow, scope: @project)
    wf.steps.create!(name: "Auto step", position: 1, allow_non_interactive: true)

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user, event_type: "slack.message")

    assert binding.valid?
  end

  test "a disabled binding skips the auto-run validation" do
    wf = create(:workflow, scope: @project)
    wf.steps.create!(name: "Manual step", position: 1, allow_non_interactive: false)

    binding = TriggerBinding.new(project: @project, workflow: wf, created_by: @user,
      event_type: "slack.message", enabled: false)

    assert binding.valid?
  end

  test "for_event scopes by project, event_type and enabled" do
    match = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "other.type")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message", enabled: false)

    event = create(:trigger_event, event_type: "slack.message", project: @project)

    assert_equal [ match.id ], TriggerBinding.for_event(event).pluck(:id)
  end

  test "a chat message matches chat triggers and the Slack triggers saved before them" do
    legacy = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    chat = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")

    event = create(:trigger_event, event_type: "chat.message", source: "slack:slack-team-T1",
                                   data: { "provider" => "slack" }, project: @project)

    assert_equal [ legacy.id, chat.id ].sort, TriggerBinding.for_event(event).pluck(:id).sort
  end

  test "a chat message from anything but its provider's receiver matches no trigger" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message")

    event = create(:trigger_event, event_type: "chat.message", source: "generic:wh-1",
                                   data: { "provider" => "slack" }, project: @project)

    assert_empty TriggerBinding.for_event(event)
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
      event_type: "slack.message",
      filter_predicate: { "text" => { "op" => "eq", "value" => "help" } })
    slashed = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message",
      filter_predicate: { "text" => { "op" => "contains", "value" => "/HELP" } })
    helpful = build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message",
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
    slack = build(:trigger_binding, event_type: "slack.message",
      filter_predicate: { "text" => { "op" => "starts_with", "value" => "deploy" } })
    webhook = build(:trigger_binding, event_type: "webhook.received",
      filter_predicate: { "text" => { "op" => "starts_with", "value" => "deploy" } })

    assert slack.matches?("text" => "Deploy staging")
    assert_not webhook.matches?("text" => "Deploy staging")
  end

  def slack_binding(**attrs)
    build(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message", **attrs)
  end

  test "save_checking_slack! refuses to create or switch on a slack trigger until the company connects Slack" do
    error = assert_raises(ActiveRecord::RecordInvalid) { slack_binding.save_checking_slack! }
    assert_includes error.record.errors.full_messages, TriggerBinding::SLACK_NOT_CONNECTED
    assert_equal 0, TriggerBinding.count

    off = slack_binding(enabled: false)
    off.save_checking_slack!
    assert off.persisted?, "a disabled slack trigger hears nothing, so it can wait for Slack"

    off.enabled = true
    assert_raises(ActiveRecord::RecordInvalid) { off.save_checking_slack! }
    assert_equal false, off.reload.enabled # rubocop:disable Minitest/RefuteFalse

    create(:integration, provider: :slack, status: :active, company: @company, project: nil)
    off.enabled = true
    off.save_checking_slack!
    assert off.reload.enabled
  end

  test "save_checking_slack! still saves other edits of a slack trigger whose workspace went away" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", name: "before")

    binding.name = "after"
    binding.save_checking_slack!

    assert_equal "after", binding.reload.name
  end

  test "save_checking_slack! reports the binding's other errors alongside the missing connection" do
    create(:step, workflow: @workflow, name: "Review copy", allow_non_interactive: false)

    error = assert_raises(ActiveRecord::RecordInvalid) { slack_binding.save_checking_slack! }

    messages = error.record.errors.full_messages.join(" ")
    assert_match(/can't run unattended/, messages)
    assert_includes messages, TriggerBinding::SLACK_NOT_CONNECTED
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
end
