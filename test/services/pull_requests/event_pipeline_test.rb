# frozen_string_literal: true

require "test_helper"

class PullRequests::EventPipelineTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:github).returns(OpenStruct.new(app_slug: "aixle-flow", webhook_secret: "secret"))
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :github, :active, company: @company, project: @project, connected_by: @user)
    @repository = create(:repository, scope: @project, integration: @integration, full_name: "acme/api")
    @workflow = create(:workflow, scope: @project)
    @column = create(:board_column, board: create(:board, project: @project), name: "Review", position: 1)
  end

  def review(verdict: "changes_requested", actor: { id: "7", name: "ada" }, revision: "r-1", **attributes)
    PullRequests::Event.build(kind: :review_submitted, number: 12, title: "Add retries", url: "https://github.com/acme/api/pull/12",
                              source_branch: "retries", target_branch: "main", author: "aixle-flow[bot]",
                              actor: actor, verdict: verdict, body: "Please handle the timeout too.", revision: revision,
                              **attributes)
  end

  def comment(id: "c-1", actor: { id: "7", name: "ada" }, body: "Rename this", **attributes)
    PullRequests::Event.build(kind: :comment_created, number: 12, title: "Add retries", url: "https://github.com/acme/api/pull/12",
                              actor: actor, body: body, comment_id: id, file: "lib/client.rb", line: 40, **attributes)
  end

  def pr_binding(event_type: "pull_request.review.submitted", **attributes)
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: event_type, **attributes)
  end

  def process(event, repositories = [ @repository ])
    PullRequests::EventPipeline.process(event, repositories)
  end

  test "a review starts the workflow with the pull request, the verdict and the reviewer in its context" do
    pr_binding(filter_predicate: { "review.verdict" => "changes_requested" })
    WorkflowService.expects(:enqueue).with do |args|
      context = args[:shared_context]["pull_request"]
      context["number"] == 12 && context["source_branch"] == "retries" && context["actor"] == "ada" &&
        context.dig("review", "verdict") == "changes_requested" && context.dig("repository", "id") == @repository.id
    end.returns(build(:workflow_run))

    event = process(review).sole

    assert_equal [ "pull_request.review.submitted", "pull_request" ], [ event.event_type, event.source ]
    assert_equal({ "id" => @repository.id, "full_name" => "acme/api", "provider" => "github" }, event.data["repository"])
    assert_equal "Please handle the timeout too.", event.data["text"]
    assert_equal false, event.data.dig("actor", "is_me") # rubocop:disable Minitest/RefuteFalse
  end

  test "a review whose verdict the trigger does not want starts nothing" do
    pr_binding(filter_predicate: { "review.verdict" => "changes_requested" })
    WorkflowService.expects(:enqueue).never

    process(review(verdict: "approved"))
  end

  test "with no pull-request trigger in the project nothing is recorded" do
    process(review)

    assert_equal 0, TriggerEvent.count
  end

  test "a trigger bound to another repository does not hear this one" do
    other = create(:repository, scope: @project, integration: @integration, full_name: "acme/web")
    pr_binding(repository: other)

    assert_empty process(review)
  end

  test "a comment carries where in the diff it was left and whether it mentions the app" do
    pr_binding(event_type: "pull_request.comment.created", filter_predicate: { "comment.mentions_me" => true })
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    process(comment(body: "@aixle-flow please rename this"))
    process(comment(id: "c-2", body: "nit: rename this"))

    data = TriggerEvent.order(:id).first.data
    assert_equal({ "id" => "c-1", "author" => "ada", "text" => "@aixle-flow please rename this", "file" => "lib/client.rb",
                   "line" => 40, "mentions_me" => true }, data["comment"])
  end

  test "a redelivered comment is recorded once" do
    pr_binding(event_type: "pull_request.comment.created")
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))

    process(comment)
    process(comment)

    assert_equal 1, TriggerEvent.count
  end

  test "the app's own review is Aixle's: ignored by default, heard when the trigger asks for it" do
    pr_binding
    hearing = pr_binding(workflow: create(:workflow, scope: @project), aixle_changes: "always")
    WorkflowService.expects(:enqueue).with { |args| args[:workflow] == hearing.workflow }.returns(build(:workflow_run))

    event = process(review(actor: { id: "99", name: "aixle-flow[bot]" })).sole

    assert_equal({ "aixle" => true, "attributed" => false, "chain" => [], "depth" => 1 }, event.data["origin"])
  end

  test "a comment a run wrote through the pull_request tools is attributed to that run and its chain" do
    pr_binding(event_type: "pull_request.comment.created", aixle_changes: "other_workflows")
    writer = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: writer, project: @project,
                                shared_context: { "pull_request" => { "chain" => [ @workflow.id ] } })
    PullRequestOperation.create!(integration: @integration, repository: @repository, operation: "add_comment",
                                 operation_key: "k-1", request_digest: "d", state: :succeeded, pull_request_number: "12",
                                 result: { "id" => "c-1" }, workflow_run_id: run.id, workflow_id: writer.id)
    WorkflowService.expects(:enqueue).never

    event = process(comment(actor: { id: "5", name: "someone" })).sole

    assert_equal [ true, true, run.id ], event.data["origin"].values_at("aixle", "attributed", "workflow_run_id")
    assert_equal [ @workflow.id, writer.id ], event.data.dig("origin", "chain")
  end

  test "a chain of Aixle's own events stops at the depth limit whatever the triggers say" do
    pr_binding(aixle_changes: "always")
    run = create(:workflow_run, workflow: @workflow, project: @project,
                                shared_context: { "pull_request" => { "chain" => [ 1, 2, 3, 4 ] } })
    PullRequestOperation.create!(integration: @integration, repository: @repository, operation: "review",
                                 operation_key: "k-2", request_digest: "d", state: :succeeded, pull_request_number: "12",
                                 result: { "verdict" => "request_changes" }, workflow_run_id: run.id, workflow_id: @workflow.id)

    assert_empty process(review)
    assert_equal 0, TriggerEvent.count
  end

  test "an event is published into each project that attached the repository and waits for it" do
    other_project = create(:project, company: @company, owner: @user)
    connection = create(:integration, :github, :active, company: @company, project: other_project, connected_by: @user)
    elsewhere = create(:repository, scope: other_project, integration: connection, full_name: "acme/api")
    create(:trigger_binding, project: other_project, workflow: create(:workflow, scope: other_project),
                             created_by: @user, event_type: "pull_request.review.submitted")
    pr_binding
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))

    events = process(review, [ @repository, elsewhere ])

    assert_equal [ @project.id, other_project.id ].sort, events.map(&:project_id).sort
  end

  test "a review with no verdict a trigger can name is dropped" do
    pr_binding

    assert_empty process(review(verdict: "dismissed"))
  end
end
