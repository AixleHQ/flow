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

  test "a comment that started the run is quoted" do
    @workflow_run.update!(shared_context: { "tracker" => {
      "handle" => "boards", "event_type" => "tracker.comment.created", "issue" => { "key" => "11" },
      "comment" => { "text" => "@Aixle\nplease look" }
    } })

    assert_match "> @Aixle\n> please look", ContextBuilders::TrackerContext.new(@session).build.sole.content
  end

  test "it stays out of runs no tracker started" do
    refute_predicate ContextBuilders::TrackerContext.new(@session), :applicable?
  end
end
