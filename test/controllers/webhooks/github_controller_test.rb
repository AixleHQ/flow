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
      check_suite: { action: "rerequested", conclusion: nil, pull_requests: [ { number: 10 } ] },
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
      check_suite: {
        action: "completed",
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
      check_suite: {
        action: "completed",
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

  test "does not enqueue job for check_suite with no pull requests" do
    payload = {
      check_suite: {
        action: "completed",
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

  private

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
