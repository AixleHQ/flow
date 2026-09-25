# frozen_string_literal: true

# Write-back endpoint for agent containers.
#
# The CLI inside a container renews its own tokens, and until this endpoint existed the
# result only reached us at session cleanup — so a container that died without cleanup (OOM
# kill, eviction, a lost node) took the rotation with it, leaving the database holding a
# refresh token the vendor had already rotated out. Under refresh-token reuse detection
# that does not just fail once; it can revoke the family.
#
# The in-container watcher posts here whenever an auth file changes, which makes the stored
# row the shared copy every holder reads and writes — the thing a single credentials file
# on a laptop gives for free, and the property production never had.
#
# Authenticated by a derived per-session key (Agents::SessionKey), not by a user session and
# not by the session's mcp_key. Only a live session may write: a finished one must not be
# able to overwrite a credential the user has since re-authenticated.
class AgentCredentialSyncController < ActionController::API
  # Auth files are small JSON documents (Claude's is well under 4 KB). The cap is what
  # stops a compromised container from posting a body big enough to matter.
  MAX_BODY_BYTES = 256 * 1024

  def create
    return head :content_too_large if request.content_length.to_i > MAX_BODY_BYTES

    session = TerminalSession.find_by(id: request.headers["X-Session-Id"])
    return unauthorized unless session&.active?
    return unauthorized unless Agents::SessionKey.valid?(session, request.headers["X-Agent-Key"])
    return unauthorized unless session.owner_entitled?

    # An auth_setup session is a login in progress: AgentAuthStrategy owns what it captures
    # and how (the design-login merge rules, the completion gate). A write-back racing that
    # would resurrect exactly the stale blocks it exists to drop.
    return head :conflict if session.session_type == "auth_setup"

    credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: session.agent_type)
    return head :not_found if credential.nil?

    files = permitted_files(credential.adapter)
    return head :unprocessable_entity if files.blank?

    persist(session, credential, files)
  end

  private

  def unauthorized
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  # Only the paths this agent's adapter names as its write-back files. The container says
  # which file it is reporting, and a container is exactly the thing that may be
  # compromised, so the path is checked against the adapter rather than trusted.
  #
  # A binary file (Kiro's SQLite login) is taken only from `files_b64`: sent as text it
  # has already been decoded as UTF-8 by an older watcher, and every byte that was not
  # UTF-8 is gone.
  def permitted_files(adapter)
    allowed = adapter.writeback_file_paths
    posted_files("files").merge(posted_files("files_b64").transform_values { |content| decode64(content) })
      .select { |path, content| allowed.include?(path) && content.present? }
      .select { |path, content| adapter.binary_writeback_path?(path) == (content.encoding == Encoding::BINARY) }
  end

  def posted_files(key)
    posted = params[key]
    return {} unless posted.respond_to?(:to_unsafe_h)

    posted.to_unsafe_h.select { |_path, content| content.is_a?(String) }
  end

  def decode64(content)
    Base64.strict_decode64(content)
  rescue ArgumentError
    nil
  end

  def persist(session, credential, files)
    captured = Agents::CredentialCapture.from_files(files, adapter: credential.adapter,
                                                           log_prefix: "AgentCredentialSync")
    return head :unprocessable_entity if captured.blank?

    # The same read-merge-write the cleanup path uses, under the same row lock. Rotations
    # only (BaseAdapter#merge_container_credentials): a token block the credential already
    # holds, fresher, same account, plausible expiry — never anything new.
    changed = credential.with_lock do
      current = credential.config_data
      merged = credential.adapter.merge_container_credentials(current, captured)
      next false if merged == current

      AgentCredential.from_artifacts(credential.user_id, credential.company_id, credential.agent_type, merged)
      true
    end

    if changed
      Rails.logger.info("[AgentCredentialSync] session=#{session.id} credential=#{credential.id} " \
                        "took a #{credential.agent_type} token rotated in the container")
    end
    head :no_content
  rescue StandardError => e
    Rails.logger.error("[AgentCredentialSync] session=#{session.id} credential=#{credential.id} failed: " \
                       "#{e.class}: #{e.message}")
    head :internal_server_error
  end
end
