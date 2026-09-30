# frozen_string_literal: true

require "test_helper"

class WorkflowResourceTest < ActiveSupport::TestCase
  setup do
    @project = create(:project, :standalone)
    @workflow = create(:workflow, scope: @project)
    create(:step, workflow: @workflow, name: "Draft")
    create(:workflow_run, :failed, workflow: @workflow).update_columns(created_at: 2.days.ago)
    @latest = create(:workflow_run, :completed, workflow: @workflow)
    @latest.update_columns(created_at: 1.hour.ago)
  end

  test "run stats serialize from the attached aggregate without querying workflow runs" do
    preloaded = Workflow.attach_run_stats(Workflow.where(id: @workflow.id).includes(:steps)).first

    payload = nil
    assert_no_queries do
      payload = WorkflowResource.new(preloaded).to_h
    end

    assert_equal 2, payload["runsCount"]
    assert_equal "completed", payload["lastRunStatus"]
    refute payload["hasActiveRuns"]
    assert_in_delta @latest.reload.created_at, Time.zone.parse(payload["lastRunAt"].to_s), 1
  end
end
