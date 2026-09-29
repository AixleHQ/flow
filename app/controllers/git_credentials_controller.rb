# frozen_string_literal: true

# Credential-vending endpoint for the in-container git credential helper, for
# GitHub and GitLab repositories (Azure has its own, AzureGitCredentialsController,
# which this mirrors). Nothing is stored in the checkout — a token in the remote URL
# would sit in .git/config, in `ps` and in the session log — so each git operation
# asks here.
#
# Authenticated by a derived per-session key (GitCredentials::SessionKey). Only a
# live session whose owner is still entitled vends, and only for a repository
# attached to that session, at that repository's own URL.
class GitCredentialsController < ActionController::API
  def create
    session = TerminalSession.find_by(id: request.headers["X-Session-Id"])
    return unauthorized unless session&.active?
    return unauthorized unless GitCredentials::SessionKey.valid?(session, request.headers["X-Git-Key"])
    return unauthorized unless session.owner_entitled?

    credential = GitCredentials::Vendor.new(session).vend!(repository_id: params[:repository_id], requested_url: params[:url])

    response.set_header("Cache-Control", "no-store")
    render json: credential.to_h, content_type: "application/json"
  rescue GitCredentials::Vendor::NotAuthorized => e
    Rails.logger.warn("[GitCredentials] session=#{session&.id} repository=#{params[:repository_id]} denied: #{e.message}")
    render json: { error: "forbidden" }, status: :forbidden
  rescue StandardError => e
    Rails.logger.error("[GitCredentials] session=#{session&.id} repository=#{params[:repository_id]} failed: #{e.class}")
    render json: { error: "unavailable" }, status: :bad_gateway
  end

  private

  def unauthorized
    Rails.logger.warn("[GitCredentials] rejected an unauthenticated credential request")
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
