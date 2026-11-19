# frozen_string_literal: true

# An MCP client that registered itself with Dynamic Client Registration
# (RFC 7591) at POST /mcp-oauth/register. Clients identified by a metadata
# document URL (CIMD) have no row here: their document is the registration.
#
# Public clients only — no secret is ever issued. What ties a code to the client
# that started the flow is PKCE, which every authorization request must carry.
class MCPAuthClient < ApplicationRecord
  CLIENT_ID_PREFIX = "aocl_"
  NAME_MAX_LENGTH = 100
  MAX_REDIRECT_URIS = 10

  validates :client_id, presence: true, uniqueness: true
  validate :redirect_uris_registrable

  def self.register!(client_name:, redirect_uris:)
    create!(client_id: "#{CLIENT_ID_PREFIX}#{SecureRandom.urlsafe_base64(24)}",
            client_name: client_name.to_s.squish.truncate(NAME_MAX_LENGTH).presence,
            redirect_uris: redirect_uris)
  end

  # Written at most once an hour: a client authorizes rarely, and this is only
  # what an operator reads to tell a live registration from an abandoned one.
  def note_use!(now = Time.current)
    return if last_used_at && last_used_at > now - 1.hour

    update_columns(last_used_at: now)
  end

  private

  def redirect_uris_registrable
    if redirect_uris.blank? || redirect_uris.size > MAX_REDIRECT_URIS
      errors.add(:redirect_uris, "must list between 1 and #{MAX_REDIRECT_URIS} URIs")
    elsif (bad = redirect_uris.reject { |uri| MCPAuth::RedirectUri.registrable?(uri) }).any?
      errors.add(:redirect_uris, "are not allowed: #{bad.join(', ')}")
    end
  end
end
