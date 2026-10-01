# frozen_string_literal: true

require "test_helper"

class Webhooks::GithubControllerTest < ActionController::TestCase
  WEBHOOK_SECRET = "test_webhook_secret"

  setup do
    @controller = Webhooks::GithubController.new
    Settings.stubs(:github).returns(
      OpenStruct.new(webhook_secret: WEBHOOK_SECRET)
    )
  end

  # == Signature verification ==

  test "rejects request with no X-Hub-Signature-256 header" do
    post_raw("{}")

    assert_response :unauthorized
  end

  test "rejects request with invalid signature" do
    @request.headers["X-Hub-Signature-256"] = "sha256=invalidsignature"
    post_raw("{}")

    assert_response :unauthorized
  end

  test "rejects request when webhook secret is blank" do
    Settings.stubs(:github).returns(OpenStruct.new(webhook_secret: nil))
    body = "{}"
    @request.headers["X-Hub-Signature-256"] = sign_payload(body)
    post_raw(body)

    assert_response :unauthorized
  end

  test "accepts correctly signed request" do
    body = "{}"
    @request.headers["X-Hub-Signature-256"] = sign_payload(body)
    @request.headers["X-GitHub-Event"] = "ping"
    post_raw(body)

    assert_response :ok
  end

  # == Event routing ==

  test "returns ok for unknown event type" do
    body = { action: "opened" }.to_json
    @request.headers["X-Hub-Signature-256"] = sign_payload(body)
    @request.headers["X-GitHub-Event"] = "pull_request"
    post_raw(body)

    assert_response :ok
  end

  test "does not enqueue job for check_suite with non-completed action" do
    payload = {
      action: "rerequested",
      check_suite: { status: "queued", conclusion: nil, pull_requests: [ { number: 10 } ] },
      repository: { full_name: "org/repo" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "does not enqueue job for check_suite with non-completed status" do
    payload = {
      action: "completed",
      check_suite: {
        status: "in_progress",
        conclusion: nil,
        pull_requests: [ { number: 10 } ]
      },
      repository: { full_name: "org/repo" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "enqueues ResolveGithubChecksJob for each PR when check_suite completed" do
    payload = {
      action: "completed",
      check_suite: {
        status: "completed",
        conclusion: "success",
        pull_requests: [ { number: 42 }, { number: 43 } ]
      },
      repository: { full_name: "org/app" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_enqueued_jobs 2, only: ResolveGithubChecksJob do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "enqueues ResolveGithubChecksJob with correct arguments" do
    payload = {
      action: "completed",
      check_suite: {
        status: "completed",
        conclusion: "failure",
        pull_requests: [ { number: 7 } ]
      },
      repository: { full_name: "org/myrepo" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_enqueued_with(job: ResolveGithubChecksJob,
                         args: [ { repo_full_name: "org/myrepo", pr_number: 7, conclusion: "failure" } ]) do
      post_raw(payload)
    end
  end

  test "does not enqueue job for check_suite with missing repository key" do
    payload = {
      action: "completed",
      check_suite: {
        status: "completed",
        conclusion: "success",
        pull_requests: [ { number: 1 } ]
      }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "does not enqueue job for check_suite with no pull requests" do
    payload = {
      action: "completed",
      check_suite: {
        status: "completed",
        conclusion: "success",
        pull_requests: []
      },
      repository: { full_name: "org/app" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "ignores pull requests with invalid numbers" do
    payload = {
      action: "completed",
      check_suite: {
        status: "completed",
        conclusion: "success",
        pull_requests: [ { number: "abc" }, {}, { number: 12 } ]
      },
      repository: { full_name: "org/app" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "check_suite"

    assert_enqueued_jobs 1, only: ResolveGithubChecksJob do
      post_raw(payload)
    end

    assert_response :ok
  end

  # == workflow_run event ==

  test "does not enqueue job for workflow_run with non-completed action" do
    payload = {
      action: "requested",
      workflow_run: { id: 1001, conclusion: nil },
      repository: { full_name: "org/repo" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "workflow_run"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "enqueues ResolveGithubWorkflowJob for workflow_run completed" do
    payload = {
      action: "completed",
      workflow_run: { id: 9999, conclusion: "success" },
      repository: { full_name: "org/app" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "workflow_run"

    assert_enqueued_jobs 1, only: ResolveGithubWorkflowJob do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "enqueues ResolveGithubWorkflowJob with correct arguments" do
    payload = {
      action: "completed",
      workflow_run: { id: 42, conclusion: "failure" },
      repository: { full_name: "org/myrepo" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "workflow_run"

    assert_enqueued_with(job: ResolveGithubWorkflowJob,
                         args: [ { repo_full_name: "org/myrepo", run_id: 42, conclusion: "failure" } ]) do
      post_raw(payload)
    end
  end

  test "does not enqueue job for workflow_run with missing repository key" do
    payload = {
      action: "completed",
      workflow_run: { id: 5, conclusion: "success" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "workflow_run"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  test "does not enqueue job for workflow_run with missing workflow_run key" do
    payload = {
      action: "completed",
      repository: { full_name: "org/app" }
    }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "workflow_run"

    assert_no_enqueued_jobs do
      post_raw(payload)
    end

    assert_response :ok
  end

  # == installation ==

  test "an uninstall on GitHub takes down the connections on that installation" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    uninstalled = github_connection(project, user, "4242")
    unrelated = github_connection(project, user, "5151")
    payload = { action: "deleted", installation: { id: 4242, account: { login: "acme-corp" } } }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "installation"
    post_raw(payload)

    assert_response :ok
    assert_equal "error", uninstalled.reload.status.to_s
    assert_equal Github::InstallationEvents::UNINSTALLED, uninstalled.settings["error"]
    assert unrelated.reload.active?
  end

  test "an installation event without an installation id changes nothing" do
    payload = { action: "deleted" }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "installation"
    post_raw(payload)

    assert_response :ok
  end

  test "an organization owner's approval of new permissions is recorded on the installation's connections" do
    company = create(:company)
    user = create(:user, company: company)
    integration = github_connection(create(:project, company: company, owner: user), user, "4242")
    payload = { action: "new_permissions_accepted",
                installation: { id: 4242, permissions: { organization_projects: "write", issues: "write" } } }.to_json

    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = "installation"
    post_raw(payload)

    assert_equal({ "organization_projects" => "write", "issues" => "write" }, integration.reload.settings["app_permissions"])
  end

  # == tracker events ==

  test "a board move on a tracked project is recorded once per delivery and processed" do
    integration = tracked_github_connection
    payload = { action: "edited", installation: { id: integration.github_installation_id }, sender: { id: 1, login: "ada" },
                projects_v2_item: { node_id: "PVTI_1", project_node_id: FakeGithub::ProjectsApi::ROADMAP,
                                    content_node_id: "I_kwDOissue1", content_type: "Issue", updated_at: "2026-10-01T10:00:00Z" },
                changes: { field_value: { field_type: "single_select", field_name: "Status",
                                          from: { id: "opt-todo", name: "Todo" }, to: { id: "opt-ready", name: "Ready for AI" } } } }.to_json

    assert_enqueued_with(job: Trackers::ProcessDeliveryJob) { deliver_tracker_event("projects_v2_item", payload, "d-1") }
    assert_no_enqueued_jobs(only: Trackers::ProcessDeliveryJob) { deliver_tracker_event("projects_v2_item", payload, "d-1") }

    subscription = integration.tracker_subscriptions.sole
    assert_equal [ "app", "active" ], [ subscription.strategy.to_s, subscription.status.to_s ]
    assert subscription.last_event_at.present?
    assert_equal [ "status" ], TrackerDelivery.sole.notification_objects.sole.changes.pluck(:field)
  end

  test "tracker events are not recorded while no tracker trigger waits for them" do
    integration = tracked_github_connection(trigger: false)
    payload = { action: "created", installation: { id: integration.github_installation_id },
                issue: { node_id: "I_kwDOissue1" }, comment: { node_id: "IC_1", body: "hi" } }.to_json

    deliver_tracker_event("issue_comment", payload, "d-2")

    assert_response :ok
    assert_equal 0, TrackerDelivery.count
  end

  private

  def tracked_github_connection(trigger: true)
    Settings.stubs(:github).returns(OpenStruct.new(webhook_secret: WEBHOOK_SECRET, app_slug: "aixle-flow"))
    integration = create(:integration, :github_projects, :active)
    Trackers::Provisioning.ensure_for!(integration)
    if trigger
      create(:trigger_binding, project: integration.project, workflow: create(:workflow, scope: integration.project),
                               created_by: integration.project.owner, event_type: "tracker.issue.status_changed")
    end
    integration
  end

  def deliver_tracker_event(event, payload, delivery_id)
    @request.headers["X-Hub-Signature-256"] = sign_payload(payload)
    @request.headers["X-GitHub-Event"] = event
    @request.headers["X-GitHub-Delivery"] = delivery_id
    post_raw(payload)
  end

  def github_connection(project, user, installation_id)
    integration = build(:integration, :github, :active, company: project.company, project: project, connected_by: user)
    integration.credentials_data = { "installation_id" => installation_id }
    integration.save!
    integration
  end

  def sign_payload(body)
    digest = OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, body)
    "sha256=#{digest}"
  end

  # Posts a raw JSON body to the :receive action.
  # Uses the `body:` kwarg so Rails 8 sets RAW_POST_DATA after recycle!, ensuring
  # request.raw_post returns the correct bytes for HMAC verification.
  def post_raw(body)
    @request.env["CONTENT_TYPE"] = "application/json"
    post :receive, body: body
  end
end
