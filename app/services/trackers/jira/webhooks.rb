# frozen_string_literal: true

module Trackers
  module Jira
    # How a Jira webhook proves where it came from.
    #
    # An admin webhook (service-account connections) is created by a Jira admin
    # with a secret, and signs its body: `X-Hub-Signature: sha256=<hex HMAC>`.
    #
    # An app webhook (3LO connections) is registered by Aixle's OAuth app and
    # carries a JWT signed with the app's client secret. Atlassian allows one URL
    # for every webhook the app registers, on every site, so it is routed by the
    # webhook ids it matched — ids unique only within a site, hence the site check.
    module Webhooks
      EVENTS = %w[jira:issue_created jira:issue_updated comment_created].freeze
      APP_PATH = "/webhooks/trackers/app/jira"
      CLOCK_SKEW = 5.minutes

      module_function

      def signed?(request, raw_body, secret)
        method, signature = request.headers["X-Hub-Signature"].to_s.split("=", 2)
        return false if secret.blank? || signature.blank? || method != "sha256"

        ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body), signature.downcase)
      end

      def app_signed?(request)
        secret = ::Jira::AppConfig.client_secret
        token = request.headers["Authorization"].to_s[/\ABearer\s+(\S+)\z/i, 1]
        return false if secret.blank? || token.blank?

        claims = JSON::JWT.decode(token, secret, [ :HS256 ])
        claims["exp"].blank? || Time.zone.at(claims["exp"].to_i) > CLOCK_SKEW.ago
      rescue JSON::JWT::Exception, ArgumentError
        false
      end

      def app_url
        "#{::Jira::AppConfig.webhook_base_url.chomp('/')}#{APP_PATH}"
      end

      # The live 3LO subscriptions an app delivery is for.
      def app_subscriptions(payload)
        ids = Array(payload["matchedWebhookIds"]).map(&:to_s).compact_blank
        return [] if ids.empty?

        site = site_of(payload)
        TrackerSubscription.live.where(strategy: "api", provider_subscription_id: ids)
                           .joins(:integration).where(integrations: { provider: "jira" }).includes(:integration)
                           .select { |subscription| same_site?(subscription.integration, site) }
      end

      # What the payload's own links say about the site: a gateway cloud id or a
      # site host. Nothing, when it carries no link.
      def site_of(payload)
        link = payload.dig("issue", "self").to_s
        return {} if link.blank?

        uri = URI.parse(link)
        { host: uri.host.to_s.downcase, cloud_id: uri.path[%r{/ex/jira/([^/]+)/}, 1] }.compact
      rescue URI::InvalidURIError
        { host: "" }
      end

      def same_site?(integration, site)
        return true if site.empty?
        return site[:cloud_id] == integration.settings.to_h["cloud_id"].to_s if site[:cloud_id]

        site[:host] == URI.parse(integration.settings.to_h["site_url"].to_s).host.to_s.downcase
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
