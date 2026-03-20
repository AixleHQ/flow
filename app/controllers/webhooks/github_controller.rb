# frozen_string_literal: true

class Webhooks::GithubController < ActionController::API
  before_action :verify_signature

  def receive
    event = request.headers["X-GitHub-Event"]

    case event
    when "check_suite"
      handle_check_suite
    end

    head :ok
  end

  private

  def handle_check_suite
    suite = params.require(:check_suite)
    return unless suite[:action] == "completed"

    repo_full_name = params.dig(:repository, :full_name)
    conclusion     = suite[:conclusion]
    pr_numbers     = suite[:pull_requests]&.map { |pr| pr[:number].to_i } || []

    pr_numbers.each do |pr_number|
      ResolveGithubChecksJob.perform_later(
        repo_full_name: repo_full_name,
        pr_number: pr_number,
        conclusion: conclusion
      )
    end
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
