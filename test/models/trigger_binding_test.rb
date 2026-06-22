# frozen_string_literal: true

require "test_helper"

class TriggerBindingTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @company)
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
    foreign_workflow = create(:workflow, scope: other_company)

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

  test "for_event scopes by project, event_type and enabled" do
    match = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "other.type")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message", enabled: false)

    event = create(:trigger_event, event_type: "slack.message", project: @project)

    assert_equal [ match.id ], TriggerBinding.for_event(event).pluck(:id)
  end
end
