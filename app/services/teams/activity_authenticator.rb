# frozen_string_literal: true

module Teams
  # Proves an inbound activity came from the Bot Framework on behalf of our bot
  # (docs/design/teams-integration.md §7.1). There is no SDK in Ruby, so this is
  # Microsoft's published checklist, rule by rule.
  module ActivityAuthenticator
    class Unauthorized < StandardError; end

    # Microsoft asks for the signing keys to be refreshed at least daily.
    KEYS_TTL = 12.hours
    CLOCK_SKEW = 5.minutes.to_i
    CACHE_KEY = "teams:bot-framework-jwks"

    module_function

    # Returns the verified claims, or raises Unauthorized naming the rule that failed.
    def authenticate!(authorization, activity)
      token = authorization.to_s[/\ABearer (.+)\z/, 1]
      raise Unauthorized, "no bearer token" if token.blank?

      kid = JWT.decode(token, nil, false).last["kid"]
      key = signing_key(kid) || signing_key(kid, refresh: true)
      raise Unauthorized, "unknown signing key" if key.nil?
      # A key is endorsed for the channels allowed to use it.
      raise Unauthorized, "key not endorsed for #{activity['channelId']}" unless
        Array(key["endorsements"]).include?(activity["channelId"].to_s)

      claims = JWT.decode(token, nil, true, algorithms: [ "RS256" ], jwks: { keys: [ key ] },
                                             iss: Config.cloud[:issuer], verify_iss: true,
                                             aud: Config.app_id, verify_aud: true, leeway: CLOCK_SKEW).first
      # The claim pins where replies go, so an activity cannot redirect them.
      raise Unauthorized, "serviceUrl does not match the token" unless claims["serviceurl"] == activity["serviceUrl"]
      raise Unauthorized, "serviceUrl is not a Bot Framework host" unless Config.service_url_allowed?(activity["serviceUrl"])

      claims
    rescue JWT::DecodeError => e
      raise Unauthorized, e.message
    end

    # An unknown kid refetches the keys (Microsoft rotates them), but at most once
    # every few minutes: anyone can send a token with a made-up kid.
    def signing_key(kid, refresh: false)
      return nil if refresh && !Rails.cache.write("#{CACHE_KEY}:refreshed", true, expires_in: 5.minutes, unless_exist: true)

      Rails.cache.delete(CACHE_KEY) if refresh
      keys = Rails.cache.fetch(CACHE_KEY, expires_in: KEYS_TTL) { fetch_keys }
      Array(keys).find { |k| k["kid"] == kid }
    end

    def fetch_keys
      metadata = get_json(Config.cloud[:openid])
      get_json(metadata.fetch("jwks_uri")).fetch("keys")
    end

    def get_json(url)
      response = Faraday.get(url)
      raise Unauthorized, "could not fetch #{url}: HTTP #{response.status}" unless response.success?

      JSON.parse(response.body)
    end
  end
end
