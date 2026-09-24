# frozen_string_literal: true

require "test_helper"

class WorkflowTriggers::CreatorTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
    @workflow = create(:workflow, scope: @project)
  end

  def create_trigger(kind, **attributes)
    WorkflowTriggers::Creator.call(project: @project, workflow: @workflow, user: @user, kind: kind, attributes: attributes)
  end

  test "column trigger binds the column with the given mode and the defaults for the rest" do
    column = create(:board_column, board: create(:board, project: @project))

    result = create_trigger("column", board_column_id: column.id, trigger_mode: "manual")

    assert_equal "column", result.kind
    binding = result.trigger
    assert_equal column, binding.board_column
    assert_equal @workflow, binding.workflow
    assert_equal @user, binding.created_by
    assert_equal "manual", binding.trigger_mode
    assert_equal 5, binding.cooldown_seconds
  end

  test "column trigger without a board raises BoardMissingError" do
    assert_raises(WorkflowTriggers::Creator::BoardMissingError) { create_trigger("column", board_column_id: 1) }
  end

  test "column trigger only binds columns of the project's own board" do
    create(:board, project: @project)
    other_project = create(:project, company: @project.company, owner: @user)
    foreign_column = create(:board_column, board: create(:board, project: other_project))

    assert_raises(ActiveRecord::RecordNotFound) { create_trigger("column", board_column_id: foreign_column.id) }
  end

  test "slack and schedule triggers get their fixed event types" do
    slack = create_trigger("slack", name: "standup")
    schedule = create_trigger("schedule", enabled: false, schedule_config: { "cron" => "0 9 * * 1-5", "timezone" => "UTC" })

    assert_equal "slack.message", slack.trigger.event_type
    assert_equal "standup", slack.trigger.name
    assert_equal "schedule.fired", schedule.trigger.event_type
    assert_equal false, schedule.trigger.enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal @project, schedule.trigger.project
  end

  test "event trigger falls back to webhook.received without an event type" do
    assert_equal "github.push", create_trigger("event", event_type: "github.push").trigger.event_type
    assert_equal "webhook.received", create_trigger("event").trigger.event_type
  end

  test "webhook trigger provisions an endpoint whose event type the binding listens on" do
    result = create_trigger("webhook", verification_strategy: "shared_token", secret: "s3cret")

    endpoint = result.webhook_endpoint
    assert_equal "shared_token", endpoint.verification_strategy
    assert_equal "s3cret", endpoint.secret
    assert_equal @project, endpoint.project
    assert_equal endpoint.config["event_type"], result.trigger.event_type
    assert_match(/\Awebhook\.\h{32}\z/, result.trigger.event_type)
  end

  test "a webhook trigger is authenticated by a generated shared token unless told otherwise" do
    endpoint = create_trigger("webhook").webhook_endpoint

    assert_equal "shared_token", endpoint.verification_strategy
    assert_predicate endpoint.secret, :present?
  end

  test "a rejected webhook binding leaves no endpoint behind" do
    assert_no_difference -> { WebhookEndpoint.count } do
      assert_raises(ActiveRecord::RecordInvalid) { create_trigger("webhook", subject_policy: "bogus") }
    end
  end

  test "an unknown kind raises UnsupportedKindError" do
    assert_raises(WorkflowTriggers::Creator::UnsupportedKindError) { create_trigger("carrier_pigeon") }
  end
end
