# frozen_string_literal: true

require "test_helper"

class Webhooks::GitlabControllerTest < ActionController::TestCase
  setup do
    @controller = Webhooks::GitlabController.new
    @company = create(:company)
    @user = create(:user, company: @company)
    @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)

    @webhook_secret = "a" * 64
    @repository = create(:repository,
      full_name: "group/app",
      integration: @integration,
      webhook_secret: @webhook_secret,
      scope: @company)
  end

  # == Authentication ==

  test "rejects request when path_with_namespace is missing" do
    post_json({})
    assert_response :unauthorized
  end

  test "rejects request when repository is not found" do
    post_json({ "project" => { "path_with_namespace" => "unknown/repo" } },
      token: @webhook_secret)
    assert_response :unauthorized
  end

  test "rejects request when X-Gitlab-Token header is missing" do
    payload = pipeline_payload(status: "success")
    @request.headers["X-Gitlab-Event"] = "Pipeline Hook"
    post :receive, body: payload.to_json, format: :json
    assert_response :unauthorized
  end

  test "rejects request when token does not match" do
    post_json(pipeline_payload(status: "success"), token: "wrongtoken")
    assert_response :unauthorized
  end

  test "rejects request when repository has no webhook_secret" do
    @repository.update_column(:webhook_secret, nil)
    post_json(pipeline_payload(status: "success"), token: @webhook_secret)
    assert_response :unauthorized
  end

  test "accepts request with correct token" do
    post_json({ "project" => { "path_with_namespace" => "group/app" },
                "object_kind" => "pipeline",
                "object_attributes" => { "id" => 1, "status" => "running" } },
      token: @webhook_secret,
      event: "push")
    assert_response :ok
  end

  # == Event routing ==

  test "does not enqueue job for non-terminal pipeline status" do
    payload = pipeline_payload(status: "running")

    assert_no_enqueued_jobs do
      post_json(payload, token: @webhook_secret, event: "Pipeline Hook")
    end

    assert_response :ok
  end

  test "enqueues ResolveGitlabPipelineJob when pipeline succeeds" do
    payload = pipeline_payload(status: "success", pipeline_id: 5000)

    assert_enqueued_with(job: ResolveGitlabPipelineJob,
      args: [ { repo_full_name: "group/app", pipeline_id: 5000,
                status: "success", mr_iid: nil } ]) do
      post_json(payload, token: @webhook_secret, event: "Pipeline Hook")
    end

    assert_response :ok
  end

  test "enqueues ResolveGitlabPipelineJob when pipeline fails" do
    payload = pipeline_payload(status: "failed", pipeline_id: 5001)

    assert_enqueued_with(job: ResolveGitlabPipelineJob,
      args: [ { repo_full_name: "group/app", pipeline_id: 5001,
                status: "failed", mr_iid: nil } ]) do
      post_json(payload, token: @webhook_secret, event: "Pipeline Hook")
    end

    assert_response :ok
  end

  test "enqueues ResolveGitlabPipelineJob when pipeline is canceled" do
    payload = pipeline_payload(status: "canceled", pipeline_id: 5002)

    assert_enqueued_with(job: ResolveGitlabPipelineJob,
      args: [ { repo_full_name: "group/app", pipeline_id: 5002,
                status: "canceled", mr_iid: nil } ]) do
      post_json(payload, token: @webhook_secret, event: "Pipeline Hook")
    end

    assert_response :ok
  end

  test "returns ok for unknown event type" do
    post_json({ "project" => { "path_with_namespace" => "group/app" } },
      token: @webhook_secret,
      event: "Push Hook")
    assert_response :ok
  end

  private

  def pipeline_payload(status:, pipeline_id: 1234)
    {
      "object_kind" => "pipeline",
      "object_attributes" => { "id" => pipeline_id, "status" => status },
      "project" => { "path_with_namespace" => "group/app" },
      "merge_request" => nil
    }
  end

  def post_json(payload, token: nil, event: "Pipeline Hook")
    @request.headers["X-Gitlab-Token"] = token if token
    @request.headers["X-Gitlab-Event"] = event
    post :receive, body: payload.to_json, format: :json
  end
end
