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
    build(:trigger_binding, project: @project, workflow: @workflow, event_type: "tracker.issue.created", **attributes)
  end

  test "a tracker binding may name only an attached tracker of its own project" do
    assert binding(project_tracker: @tracker).valid?

    @tracker.detach!
    refute_predicate binding(project_tracker: @tracker), :valid?
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
