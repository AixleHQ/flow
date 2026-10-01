# frozen_string_literal: true

require "test_helper"

class TriggerBindingTrackerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @tracker = create(:project_tracker, integration: @integration)
    @workflow = create(:workflow, scope: @project)
  end

  def binding(**attributes)
    build(:trigger_binding, **{ project: @project, workflow: @workflow, event_type: "tracker.issue.created" }.merge(attributes))
  end

  test "a tracker binding may name only an attached tracker of its own project" do
    assert binding(project_tracker: @tracker).valid?

    @tracker.detach!
    refute_predicate binding(project_tracker: @tracker), :valid?
  end

  test "a binding keeps the tracker it names through a detach, so it stays editable without widening" do
    kept = binding(project_tracker: @tracker).tap(&:save!)
    elsewhere = binding.tap(&:save!)
    @tracker.detach!

    assert kept.reload.update(aixle_changes: "always", filter_predicate: { "issue.type" => "Bug" })
    assert_equal @tracker.id, kept.project_tracker_id
    refute elsewhere.update(project_tracker: @tracker)
    assert_includes elsewhere.errors[:project_tracker], "must be an attached tracker of this project"
  end

  test "a workflow takes a tracker trigger once: a copy would start it twice per event" do
    column = { "change.to.name" => { "op" => "in", "value" => [ "Ready for AI" ] } }
    original = binding(project_tracker: @tracker, filter_predicate: column).tap(&:save!)

    copy = binding(project_tracker: @tracker, filter_predicate: column.deep_dup)
    refute_predicate copy, :valid?
    assert_includes copy.errors[:workflow], "already has a trigger for this tracker event with the same conditions"

    assert binding(project_tracker: @tracker, filter_predicate: { "change.to.name" => { "op" => "in", "value" => [ "Review" ] } }).valid?
    assert binding(filter_predicate: column).valid?, "any tracker is a different trigger"
    assert binding(project_tracker: @tracker, filter_predicate: column, workflow: create(:workflow, scope: @project)).valid?
    assert original.update(aixle_changes: "always"), "saving the original is not a copy of itself"
  end

  test "a binding scoped to one tracker matches only that tracker's events" do
    scoped = binding(project_tracker: @tracker)

    assert scoped.matches?({ "tracker" => { "id" => @tracker.id } })
    refute scoped.matches?({ "tracker" => { "id" => @tracker.id + 1 } })
    assert binding.matches?({ "tracker" => { "id" => @tracker.id + 1 } }), "no tracker means any"
  end

  test "creating an enabled tracker binding makes its tracker deliver events" do
    assert_enqueued_with(job: Trackers::EnsureEventDeliveryJob, args: [ @tracker.id ]) do
      binding(project_tracker: @tracker).save!
    end
  end

  test "when a connection is removed, its trackers' triggers stop rather than widen to any tracker" do
    saved = binding(project_tracker: @tracker).tap(&:save!)

    @integration.destroy!

    saved.reload
    assert_equal [ false, nil ], [ saved.enabled, saved.project_tracker_id ]
  end
end
