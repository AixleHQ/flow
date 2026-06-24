# frozen_string_literal: true

require "test_helper"

class ScheduleReconcilerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.company)
    @workflow = create(:workflow, scope: @project)
  end

  def schedule_binding(enabled: true, cron: "0 9 * * 1-5")
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "schedule.fired", enabled: enabled,
      schedule_config: { "cron" => cron, "timezone" => "UTC" })
  end

  test "reconcile deletes the old schedule then creates one from the config" do
    binding = schedule_binding
    TemporalService.expects(:delete_binding_schedule).with("schedule-trigger-#{binding.id}").once
    TemporalService.expects(:create_binding_schedule).with(
      has_entries(schedule_id: "schedule-trigger-#{binding.id}", cron: "0 9 * * 1-5", timezone: "UTC")
    ).once

    ScheduleReconciler.reconcile(binding)
  end

  test "reconcile only deletes when the binding is disabled" do
    binding = schedule_binding(enabled: false)
    TemporalService.expects(:delete_binding_schedule).once
    TemporalService.expects(:create_binding_schedule).never

    ScheduleReconciler.reconcile(binding)
  end

  test "remove deletes the schedule by binding id" do
    TemporalService.expects(:delete_binding_schedule).with("schedule-trigger-42").once
    ScheduleReconciler.remove(42)
  end

  test "saving a schedule binding enqueues reconciliation (off the request)" do
    assert_enqueued_jobs(1, only: ScheduleReconcileJob) do
      schedule_binding
    end
  end

  test "destroying a schedule binding enqueues removal" do
    binding = schedule_binding
    assert_enqueued_with(job: ScheduleReconcileJob, args: [ "remove", binding.id ]) do
      binding.destroy
    end
  end
end
