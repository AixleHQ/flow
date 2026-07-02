# frozen_string_literal: true

require "test_helper"

class ScheduleReconcilerTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
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

  test "saving a schedule binding reconciles inline when Temporal is enabled" do
    TemporalService.stubs(:enabled?).returns(true)
    TemporalService.stubs(:delete_binding_schedule)
    TemporalService.expects(:create_binding_schedule).once

    schedule_binding
  end

  test "destroying a schedule binding removes its schedule inline" do
    binding = schedule_binding # created with Temporal off in test → no reconcile on create
    TemporalService.stubs(:enabled?).returns(true)
    TemporalService.expects(:delete_binding_schedule).with("schedule-trigger-#{binding.id}").once

    binding.destroy
  end

  test "reconcile_all (re)creates schedules for enabled schedule bindings only" do
    enabled = schedule_binding(enabled: true)
    schedule_binding(enabled: false) # disabled → skipped

    TemporalService.stubs(:delete_binding_schedule)
    TemporalService.expects(:create_binding_schedule).with(
      has_entry(schedule_id: "schedule-trigger-#{enabled.id}")
    ).once

    ScheduleReconciler.reconcile_all
  end
end
