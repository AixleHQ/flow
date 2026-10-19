# frozen_string_literal: true

require "test_helper"

class ContextBuilders::TrackerContextTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, :admin, company: company)
    @project = create(:project, company: company, owner: @user)
    workflow = create(:workflow, scope: @project)
    @workflow_run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: @workflow_run, step: create(:step, workflow: workflow))
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)
  end

  test "a run a tracker event started is told which issue, which tracker, and what changed" do
    @workflow_run.update!(shared_context: { "tracker" => {
      "handle" => "boards", "event_type" => "tracker.issue.status_changed",
      "issue" => { "key" => "11", "title" => "It breaks", "url" => "https://dev.azure.com/acme/p/_workitems/edit/11" },
      "change" => { "field" => "status", "from" => { "name" => "New" }, "to" => { "name" => "Ready for AI" } }
    } })

    content = ContextBuilders::TrackerContext.new(@session).build.sole.content

    assert_match "[11 It breaks](https://dev.azure.com/acme/p/_workitems/edit/11)", content
    assert_match "`boards` tracker changed status (New → Ready for AI)", content
    assert_match "tracker_get_issue", content
  end

  test "the run is told about the issue's files: what is already in its workspace and what was left out" do
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    @workflow_run.update!(board_task: task, shared_context: { "tracker" => {
      "handle" => "jira", "event_type" => "tracker.issue.created", "issue" => { "key" => "ENG-1" },
      "files" => { "copied" => 1, "skipped" => [ { "name" => "dump.png", "reason" => "restricted" } ] }
    } })
    copy = task.task_assets.create!(name: "trace.log", source: :tracker, file: StringIO.new("t"))
    TrackerAttachment.create!(project: @project, provider: "jira", instance: "c1", issue_id: "10100", external_id: "1",
                              direction: :imported, content_sha256: "s", task_asset: copy, data: { "issue_key" => "ENG-1" })

    content = ContextBuilders::TrackerContext.new(@session).build.sole.content

    assert_match "tracker_download_attachments", content
    assert_match "`/workspace/tracker/ENG-1/trace.log`", content
    assert_match "Not copied: dump.png (restricted)", content
  end

  test "a comment that started the run is quoted" do
    @workflow_run.update!(shared_context: { "tracker" => {
      "handle" => "boards", "event_type" => "tracker.comment.created", "issue" => { "key" => "11" },
      "comment" => { "text" => "@Aixle\nplease look" }
    } })

    assert_match "> @Aixle\n> please look", ContextBuilders::TrackerContext.new(@session).build.sole.content
  end

  test "a run that can change code is told to carry the issue key in branch names and pull-request titles" do
    @workflow_run.update!(shared_context: { "tracker" => {
      "handle" => "jira", "event_type" => "tracker.issue.created", "issue" => { "key" => "ENG-123", "id" => "10001" }
    } })
    integration = create(:integration, :gitlab, :active, company: @project.company)
    @session.repositories << create(:repository, scope: @project, integration: integration, full_name: "team/app",
                                                 clone_url: "https://gitlab.com/team/app.git")

    content = ContextBuilders::TrackerContext.new(@session.reload).build.sole.content

    assert_match "start branch names with `ENG-123` (`ENG-123-short-description`)", content
    assert_match "`ENG-123: …`", content
  end

  test "without a code repository there is nothing to name after the issue" do
    @workflow_run.update!(shared_context: { "tracker" => {
      "handle" => "jira", "event_type" => "tracker.issue.created", "issue" => { "key" => "ENG-123" }
    } })
    @session.repositories << create(:repository, :public_source, scope: @project, full_name: "torvalds/linux",
                                                                 clone_url: "https://github.com/torvalds/linux.git")

    assert_no_match "branch names", ContextBuilders::TrackerContext.new(@session.reload).build.sole.content
  end

  test "it stays out of runs no tracker started" do
    refute_predicate ContextBuilders::TrackerContext.new(@session), :applicable?
  end
end
