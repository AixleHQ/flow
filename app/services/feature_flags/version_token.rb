# frozen_string_literal: true

module FeatureFlags
  # The change signal between processes: a writer sets a new random token after
  # it commits, and every FeatureFlags::Store reloads when the token it last saw
  # differs. Through the Redis client directly rather than Rails.cache, whose
  # entries expire after a day (a lost token hides changes until max staleness)
  # and which is a null store in test.
  #
  # Redis being down never raises: `read` answers nil and the store falls back to
  # its max-staleness reload; a failed `bump` is reported, and the change still
  # reaches every process within max staleness.
  class VersionToken
    KEY = "feature_flags:version"
    # A check runs on a request's thread, so an unreachable Redis must cost it
    # milliseconds, not the client's default seconds.
    TIMEOUT_SECONDS = 0.25

    def initialize(url: Settings.redis.url, key: KEY)
      @url = url
      @key = key
    end

    def read
      redis.get(@key)
    rescue Redis::BaseError => e
      Rails.logger.warn("[FeatureFlags] version token unreadable, relying on max staleness: #{e.class}: #{e.message}")
      nil
    end

    def bump
      token = SecureRandom.uuid
      redis.set(@key, token)
      token
    rescue Redis::BaseError => e
      Rails.error.report(e, handled: true, severity: :warning, source: VERSION_BUMP_FAILED_SOURCE,
                            context: { error_class: e.class.name })
      nil
    end

    private

    def redis
      @redis ||= Redis.new(url: @url, connect_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS,
                           write_timeout: TIMEOUT_SECONDS, reconnect_attempts: 0)
    end
  end
end
