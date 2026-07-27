# frozen_string_literal: true

module CloudAuth
  # Session-start preflight for cloud connections, mirroring Oauth::Preflight.
  #
  # This is what closes the chicken-and-egg problem. A credential source inside the
  # container cannot talk to the user, and Claude Code hides Bedrock errors — so a dead
  # connection would surface as an agent that simply does not answer. Catching it before
  # launch lets the caller return a "Reconnect AWS" CTA instead.
  #
  # No network: this only catches never-connected, structurally incomplete, and
  # dead-and-unrefreshable connections. The live exchange still happens at vending time.
  module Preflight
    # Where a "Reconnect AWS" CTA sends the user: the profile page, with a query param that
    # opens the AGENT AUTH modal. Reconnecting deliberately goes through the same door as
    # connecting did — the user picks Amazon Bedrock in Claude Code's own wizard and the
    # auth modal offers the connect step — rather than a second, separate cloud entry point.
    CONNECT_PATH = "/profile?authenticate=claude_code"

    module_function

    # @param user [User]
    # @return [Array<Hash>] one entry per broken connection:
    #   { provider:, name:, reason:, connect_url: }. Empty when nothing is wrong —
    #   including for a user who has no cloud connection at all, since not using
    #   Bedrock is not a problem to report.
    def broken_connections(user)
      credential = user&.agent_credentials&.find_by(agent_type: "claude_code")
      return [] if credential.nil?

      block = credential.config_data[Agents::ClaudeCodeAdapter::BEDROCK_KEY]
      return [] unless block.is_a?(Hash)

      reason = unusable_reason(block)
      return [] if reason.nil?

      [ {
        provider: "aws",
        name: connection_name(block),
        reason: reason,
        connect_url: CONNECT_PATH
      } ]
    end

    # nil means usable.
    def unusable_reason(block)
      # A Bedrock API key or long-term access keys, entered in Claude Code's own wizard and
      # harvested from its settings file: both carry everything in env and need no
      # server-side exchange, so nothing here can rot.
      return nil if block["bearer_token"].present?
      return nil if block.dig("static_credentials", "access_key_id").present?

      idc = block["identity_center"]
      return "not_connected" unless idc.is_a?(Hash)
      return "not_connected" if idc["account_id"].blank? || idc["role_name"].blank?

      registration = idc["registration"] || {}
      return "not_connected" if registration["client_id"].blank?
      # Identity Center caps client registrations at 90 days and refresh cannot cross
      # that boundary — only a fresh device flow recovers.
      return "registration_expired" if past?(registration["expires_at"])

      token = idc["token"] || {}
      return "not_connected" if token["access_token"].blank? && token["refresh_token"].blank?
      return "reauthorization_required" if token["refresh_token"].blank? && past?(token["expires_at"])

      nil
    end

    def connection_name(block)
      idc = block["identity_center"] || {}
      account = idc["account_id"]
      role = idc["role_name"]
      return "AWS Bedrock" if account.blank?

      role.present? ? "AWS #{account} / #{role}" : "AWS #{account}"
    end

    def past?(value)
      return false if value.blank?

      # Time.zone.parse returns nil for unparseable input rather than raising, so the
      # rescue alone is not enough. Garbage counts as expired — better to prompt a
      # reconnect than to hand a broken connection to a session.
      parsed = Time.zone.parse(value.to_s)
      parsed.nil? || parsed <= Time.current
    rescue ArgumentError, TypeError
      true
    end
  end
end
