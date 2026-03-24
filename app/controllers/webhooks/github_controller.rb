# frozen_string_literal: true

class Webhooks::GithubController < ActionController::API
  before_action :verify_signature

  def receive
    event = request.headers["X-GitHub-Event"]

    case event
    when "check_suite"
      handle_check_suite
    when "workflow_run"
      handle_workflow_run
    end

    head :ok
  end

  private

  def handle_check_suite
    payload = request.request_parameters
    return unless payload["action"] == "completed"

    suite = payload["check_suite"]
    return unless suite.is_a?(Hash)
    return unless suite["status"] == "completed"

    repo_full_name = payload.dig("repository", "full_name")
    return if repo_full_name.blank?

    conclusion = suite["conclusion"]
    pr_numbers = Array(suite["pull_requests"]).filter_map do |pull_request|
      next unless pull_request.is_a?(Hash)

      Integer(pull_request["number"], exception: false)
    end

    pr_numbers.each do |pr_number|
      ResolveGithubChecksJob.perform_later(
        repo_full_name: repo_full_name,
        pr_number: pr_number,
        conclusion: conclusion
      )
    end
  end

  def handle_workflow_run
    payload = request.request_parameters
    return unless payload["action"] == "completed"

    workflow_run = payload["workflow_run"]
    return unless workflow_run.is_a?(Hash)

    repo_full_name = payload.dig("repository", "full_name")
    return if repo_full_name.blank?

    run_id = Integer(workflow_run["id"], exception: false)
    return unless run_id

    conclusion = workflow_run["conclusion"]

    ResolveGithubWorkflowJob.perform_later(
      repo_full_name: repo_full_name,
      run_id: run_id,
      conclusion: conclusion
    )
  end

  def verify_signature
    secret = Settings.github.webhook_secret
    return head :unauthorized if secret.blank?

    sig_header = request.headers["X-Hub-Signature-256"]
    return head :unauthorized if sig_header.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(sig_header, expected)
  end
end
