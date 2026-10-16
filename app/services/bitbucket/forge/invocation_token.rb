# frozen_string_literal: true

module Bitbucket
  module Forge
    # The Forge Invocation Token every remote call carries
    # (https://developer.atlassian.com/platform/forge/forge-remote-invocation-contract).
    # Nothing a Forge request says is believed before this verifies it; the
    # installation, workspace and user come from its claims, never from the body.
    class InvocationToken
      class Invalid < StandardError; end

      ISSUER = "forge/invocation-token"
      ALGORITHM = "RS256"
      CLOCK_SKEW = 60
      KEYS_TTL = 12.hours
      CACHE_KEY = "bitbucket:forge-jwks"

      attr_reader :claims

      def self.verify!(authorization)
        token = authorization.to_s[/\ABearer (.+)\z/, 1]
        raise Invalid, "no invocation token" if token.blank?

        header = JWT.decode(token, nil, false).last
        # Pinned rather than read from the header: `none` and HS256 are how a
        # forged token gets past a verifier that trusts `alg`.
        raise Invalid, "unexpected signing algorithm #{header['alg'].inspect}" unless header["alg"] == ALGORITHM

        key = signing_key(header["kid"]) || signing_key(header["kid"], refresh: true)
        raise Invalid, "unknown signing key" if key.nil?

        claims = JWT.decode(token, nil, true, algorithms: [ ALGORITHM ], jwks: { keys: [ key ] },
                                               iss: ISSUER, verify_iss: true, leeway: CLOCK_SKEW,
                                               required_claims: %w[exp iss aud]).first
        new(claims).tap(&:check!)
      rescue JWT::DecodeError => e
        raise Invalid, e.message
      end

      # An unknown kid refetches the keys, but at most once a few minutes: anyone
      # can send a token naming a made-up kid.
      def self.signing_key(kid, refresh: false)
        return if kid.blank?
        return if refresh && !Rails.cache.write("#{CACHE_KEY}:refreshed", true, expires_in: 5.minutes, unless_exist: true)

        Rails.cache.delete(CACHE_KEY) if refresh
        keys = Rails.cache.fetch(CACHE_KEY, expires_in: KEYS_TTL) { fetch_keys }
        Array(keys).find { |k| k["kid"] == kid }
      end

      def self.fetch_keys
        response = Faraday.new(request: { open_timeout: 3, timeout: 5 }).get(AppConfig.forge_jwks_url)
        raise Invalid, "could not fetch the Forge signing keys (HTTP #{response.status})" unless response.success?

        JSON.parse(response.body).fetch("keys")
      rescue Faraday::Error, JSON::ParserError, KeyError => e
        raise Invalid, "could not fetch the Forge signing keys (#{e.class.name.demodulize})"
      end

      def initialize(claims)
        @claims = claims
      end

      def check!
        unless Array(claims["aud"]).any? { |aud| Ids.same?(aud, AppConfig.forge_app_id) }
          raise Invalid, "issued for another app"
        end
        raise Invalid, "issued for another environment" unless Ids.same?(environment_id, AppConfig.forge_environment_id)
        raise Invalid, "names no installation" if installation_id.blank?
        raise Invalid, "names no Bitbucket workspace" if workspace_uuid.blank?
      end

      def installation_id
        claims.dig("app", "installationId").presence || claims.dig("app", "installation", "id").presence
      end

      def environment_id = Ids.tail(claims.dig("app", "environment", "id"))

      def workspace_uuid
        context = Array(claims.dig("app", "installation", "contexts")).find { |c| c.is_a?(Hash) && c["workspaceId"].present? }
        Ids.uuid(context&.dig("workspaceId") || claims.dig("context", "workspaceId") || claims.dig("context", "workspace", "uuid"))
      end

      # The Atlassian account that opened a UI module; nil for events and schedules.
      def principal = claims["principal"].presence

      def module_key = claims.dig("app", "module", "key")
      def app_version = claims.dig("app", "appVersion").presence
    end
  end
end
