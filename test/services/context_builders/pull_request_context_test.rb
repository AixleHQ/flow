# frozen_string_literal: true

require "test_helper"

class ContextBuilders::PullRequestContextTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, :admin, company: company)
    @project = create(:project, company: company, owner: @user)
    workflow = create(:workflow, scope: @project)
    @workflow_run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: @workflow_run, step: create(:step, workflow: workflow))
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)
    @repository = create(:repository, scope: @project, full_name: "acme/api",
                                      integration: create(:integration, :github, :active, company: company, project: @project))
  end

  def started_by(context)
    @workflow_run.update!(shared_context: { "pull_request" => {
      "event_type" => "pull_request.review.submitted", "number" => 12, "title" => "Add retries",
      "url" => "https://github.com/acme/api/pull/12", "source_branch" => "retries", "target_branch" => "main",
      "repository" => { "id" => @repository.id, "full_name" => "acme/api", "provider" => "github" }, "actor" => "ada"
    }.merge(context) })
    ContextBuilders::PullRequestContext.new(@session).build.sole.content
  end

  test "a run a review started is told who asked for what, on which branch, and how to answer" do
    @session.repositories << @repository

    content = started_by("review" => { "verdict" => "changes_requested", "body" => "Handle the timeout" })

    assert_match "ada requested changes on [pull request #12 \"Add retries\"](https://github.com/acme/api/pull/12) in `acme/api`", content
    assert_match "Its branch is `retries` (into `main`).", content
    assert_match "> Handle the timeout", content
    assert_match "switch to `retries`", content
    assert_match "pull_request_list_comments` (repository_id #{@repository.id}, pull_request 12)", content
  end

  test "a comment names its place in the diff, and a repository the step did not attach is said to be missing" do
    content = started_by("event_type" => "pull_request.comment.created",
                         "comment" => { "text" => "Rename this", "file" => "lib/client.rb", "line" => 40 })

    assert_match "ada commented on", content
    assert_match "at `lib/client.rb:40`", content
    assert_match "not attached to this session", content
  end

  test "a comment that came without the branch sends the agent to read it from the pull request" do
    @session.repositories << @repository

    content = started_by("event_type" => "pull_request.comment.created", "source_branch" => nil, "target_branch" => nil,
                         "comment" => { "text" => "Rename this" })

    assert_match "the pull request's branch is not in the event, so read it with the pull request", content
    assert_no_match "Its branch is", content
  end

  test "an Azure DevOps run is pointed at Azure's own thread tools" do
    azure = create(:repository, :azure_devops, scope: @project,
                                               integration: create(:integration, :azure_devops, :active, company: @project.company, project: @project))
    @session.repositories << azure

    content = started_by("repository" => { "id" => azure.id, "full_name" => azure.full_name, "provider" => "azure_devops" },
                         "review" => { "verdict" => "approved" })

    assert_match "azure_devops_list_pull_request_threads` (repository_id #{azure.id}, pull_request_id 12)", content
    assert_no_match "pull_request_list_comments", content
  end

  test "a vote with no text quotes nothing, so it carries no warning about quoted text" do
    content = started_by("review" => { "verdict" => "approved" })

    assert_match "ada approved", content
    assert_no_match "This text is from the pull request", content
  end

  test "a follow-up run is told the comments it covers arrived while an earlier run worked" do
    event = TriggerEvent.create!(event_type: "pull_request.comment.created", source: "pull_request", subject: "github:acme/api#12",
                                 project_id: @project.id, occurred_at: Time.current)
    TriggerDispatch.create!(trigger_event: event, workflow_run: @workflow_run, source: "trigger_binding:1", dedup_key: SecureRandom.hex,
                            status: "started", detail: { "follows_run" => 41, "events" => 3 })

    content = started_by("event_type" => "pull_request.comment.created", "comment" => { "text" => "Rename this" })

    assert_match "These 3 reviews and comments arrived while an earlier run was working on the pull request", content
  end

  test "a run nothing on a pull request started gets no such section" do
    assert_not ContextBuilders::PullRequestContext.new(@session).applicable?
  end
end
