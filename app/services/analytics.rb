# frozen_string_literal: true

# Product analytics (PostHog), the one door every server-side event goes through.
#
# Sends only from the hosted product with a key configured, never while a super
# admin impersonates someone, and only for a person who said yes: the person an
# event is attributed to must have granted consent, whoever caused it. Events
# leave through a job, so a PostHog outage costs the event and never the request.
#
# Every property is an id, an enum or a count. Nothing a person typed goes out.
module Analytics
  VIAS = %w[ui mcp integration system].freeze
  ONBOARDING_STATES = { "step1" => "profile", "step2" => "agents", "completed" => "completed" }.freeze
  # Read by the client banner on pages where nobody is signed in yet, and adopted
  # onto the account at sign-in (Web::ApplicationController).
  CONSENT_COOKIE = "analytics_consent"

  class << self
    def enabled?
      Deployment.saas? && Settings.posthog.api_key.present? && (!Rails.env.development? || Settings.posthog.enable_in_dev)
    end

    # An event a person is answerable for: `user` is who it is attributed to,
    # and whose consent decides whether it is sent.
    def capture(event, user:, company: nil, project: nil, props: {}, via: nil)
      return unless sendable? && user&.analytics_consent_granted?

      deliver(event: event, distinct_id: user.id.to_s,
              properties: Context.props(user: user, company: company, project: project,
                                        via: via || Current.analytics_via || "system").merge(props))
    rescue StandardError => e
      report(e, event)
    end

    # The same, attributed to whoever is acting in this request or tool call
    # (Current.analytics_actor). Nothing is sent when nobody is: a change a job
    # made on its own is not a person using the product.
    def track(event, company:, project: nil, props: {})
      actor = Current.analytics_actor
      return if actor.nil?

      capture(event, user: actor, company: company, project: project, props: props)
    end

    # Before there is an account: the browser's anonymous id, sent only when
    # consent was given on the page the id comes from.
    def capture_anonymous(event, distinct_id:, props: {})
      return unless sendable? && distinct_id.present?

      deliver(event: event, distinct_id: distinct_id.to_s,
              properties: { "via" => "ui", "app_version" => Settings.app.version, "$process_person_profile" => false }
                            .merge(props.stringify_keys))
    rescue StandardError => e
      report(e, event)
    end

    # Joins what a browser did before signing up to the account it signed up as,
    # even when the confirmation link was opened somewhere else.
    def alias_anonymous(user:, anonymous_id:)
      return unless sendable? && user&.analytics_consent_granted? && anonymous_id.present?
      return if anonymous_id.to_s == user.id.to_s

      deliver(event: "$create_alias", distinct_id: user.id.to_s,
              properties: { "distinct_id" => user.id.to_s, "alias" => anonymous_id.to_s })
    rescue StandardError => e
      report(e, "$create_alias")
    end

    # What the browser needs to report this page, or nil where it must not
    # (Web::ApplicationController#analytics_share).
    def browser_config(user:, company:, capture:)
      return nil unless sendable?

      {
        key: Settings.posthog.api_key,
        host: Settings.posthog.host,
        capture: capture,
        consent: user&.analytics_consent,
        distinct_id: user&.id&.to_s,
        signup_date: user && Context.signup_date(user),
        context: user ? Context.props(user: user, company: company).except("$set_once", "via", "$geoip_disable") : {}
      }
    end

    def first_for_company?(scope, record)
      !scope.where.not(id: record.id).exists?
    end

    private

    def sendable?
      enabled? && Current.user_session&.impersonator_id.blank?
    end

    def deliver(event:, distinct_id:, properties:)
      CaptureJob.perform_later(
        "event" => event, "distinct_id" => distinct_id, "properties" => properties.deep_stringify_keys,
        "timestamp" => Time.current.iso8601(3), "uuid" => SecureRandom.uuid
      )
    end

    def report(error, event)
      Rails.logger.warn("[Analytics] #{event} not sent: #{error.class}: #{error.message}")
    end
  end
end
