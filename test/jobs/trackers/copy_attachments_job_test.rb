# frozen_string_literal: true

require "test_helper"

# Copying an issue's files when a tracker trigger starts a run
# (docs/design/tracker-attachments.md §7.5).
class Trackers::CopyAttachmentsJobTest < ActiveJob::TestCase
  ISSUE_1 = FakeYoutrack::Api::ISSUE_1

  setup do
    @youtrack = stub_youtrack!
    @integration = create(:integration, :youtrack, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @tracker = ProjectTracker.find_by!(project: @project, external_scope_id: FakeYoutrack::Api::APP)
    board = create(:board, project: @project)
    @task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    @run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @project.owner,
                                 board_task: @task, shared_context: {
                                   "tracker" => { "project_tracker_id" => @tracker.id, "issue" => { "id" => ISSUE_1, "key" => "APP-1" } },
                                   "outputs" => { "kept" => true }
                                 })
  end

  test "the issue's files land on the run's task, and what was left out goes into the run's context" do
    @youtrack.add_file(ISSUE_1, name: "log.txt", bytes: "boom")
    @youtrack.add_file(ISSUE_1, name: "secret.txt", bytes: "s", restricted: true)

    Trackers::CopyAttachmentsJob.perform_now(@run.id)

    assert_equal [ [ "log.txt", "tracker" ] ], @task.task_assets.map { |a| [ a.name, a.source ] }
    context = @run.reload.shared_context
    assert_equal({ "copied" => 1, "skipped" => [ { "name" => "secret.txt", "reason" => "restricted" } ] }, context.dig("tracker", "files"))
    assert_equal({ "kept" => true }, context["outputs"])
  end

  test "a run not yet readable is tried again" do
    run_id = @run.id
    @run.destroy!

    Trackers::CopyAttachmentsJob.perform_now(run_id)

    assert_enqueued_with(job: Trackers::CopyAttachmentsJob, args: [ run_id ])
  end
end
