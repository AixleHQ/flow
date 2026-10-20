# frozen_string_literal: true

module Gitlab
  # Keeps a service-account connection's token alive
  # (docs/design/gitlab-tracker.md §4). A group that requires token expiry
  # gives at most a year; the token rotates itself a month ahead, asking for
  # the longest lifetime the group allows. GitLab's own default for a rotation
  # without a date is one week, which is never what the connection wants.
  module ServiceAccountToken
    WINDOW = 30.days
    LIFETIMES = [ 365, 180, 90, 30 ].freeze

    module_function

    def due?(integration)
      expires_at = integration.settings.to_h["token_expires_at"]
      integration.settings.to_h["auth_mode"] == IntegrationService::SERVICE_ACCOUNT_MODE && expires_at.present? &&
        Date.parse(expires_at.to_s) <= WINDOW.from_now.to_date
    end

    # Only the token: the account outlives the connection, since only a group
    # Owner may delete it.
    def revoke(token)
      return if token.blank?

      Rest.new(token: token).delete("/personal_access_tokens/self")
    rescue Trackers::Error => e
      Rails.logger.warn("[Gitlab::ServiceAccountToken] could not revoke a token: #{e.code}")
    end

    def rotate!(integration)
      rest = Rest.for(integration)
      raw = nil
      LIFETIMES.each do |days|
        raw = rest.post("/personal_access_tokens/self/rotate", { expires_at: (Date.current + days).iso8601 })
        break
      rescue Trackers::Error => e
        raise unless e.code == "validation_failed" && days != LIFETIMES.last
      end
      integration.credentials_data = integration.credentials_data.merge(
        "personal_access_token" => raw["token"], "service_account_token_id" => raw["id"].to_s
      )
      integration.settings = integration.settings.to_h.merge("token_expires_at" => raw["expires_at"])
      integration.save!
      integration
    end
  end
end
