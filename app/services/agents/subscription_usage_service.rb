# frozen_string_literal: true

module Agents
  # Plan-usage windows (Claude's rolling 5-hour and weekly limits) for every
  # credential on a membership that reports them.
  #
  # Cached per credential because the vendor endpoint is bucketed per client and
  # answers 429 to anything chatty — and the profile page would otherwise call it
  # on every render, including the partial reloads Inertia fires for other props.
  # The cache key carries the credential's updated_at, so a re-auth or a rotated
  # token invalidates it for free: a credential that has just switched from a
  # subscription to Bedrock never keeps serving the windows it used to have.
  class SubscriptionUsageService
    # Anthropic's usage endpoint tolerates a poll every ~180s; hold that as the
    # floor for a successful answer.
    OK_TTL = 3.minutes
    # A failure gets a shorter hold so a transient error doesn't pin the panel
    # for a full period.
    ERROR_TTL = 1.minute
    # How stale a cached answer must be before the "Refresh" button actually
    # re-fetches. Without it the button is a 429 generator.
    MIN_REFRESH_INTERVAL = 30.seconds

    # Resolving an agent_type to its adapter is the seam this service is tested
    # through: the vendor HTTP call lives in the adapter (and is contract-tested
    # there), so caching and throttling can be exercised without a network stub.
    DEFAULT_ADAPTER_RESOLVER = ->(agent_type) { AgentCredentialsService.for(agent_type).adapter }

    # @param membership [CompanyMembership, nil] nil for a super admin (no credentials)
    # @param force [Boolean] user asked for a refresh (still throttled)
    # @param adapter_resolver [#call] agent_type -> adapter (test seam)
    def initialize(membership:, force: false, adapter_resolver: DEFAULT_ADAPTER_RESOLVER)
      @membership = membership
      @force = force
      @adapter_resolver = adapter_resolver
    end

    # @return [Array<Hash>] one entry per credential that reports usage windows:
    #   { agent_type:, status:, windows:, extra_usage:, fetched_at: }
    def call
      return [] if @membership.nil?

      @membership.credentials.filter_map { |credential| usage_for(credential) }
    end

    private

    def usage_for(credential)
      cached = Rails.cache.read(cache_key(credential))
      return cached if cached && !refetch?(cached)

      usage = adapter_for(credential).fetch_subscription_usage(credential.config_data)
      return nil if usage.nil? # not a subscription login — nothing to show

      entry = usage.merge(agent_type: credential.agent_type, fetched_at: Time.current)
      Rails.cache.write(cache_key(credential), entry, expires_in: entry[:status] == "ok" ? OK_TTL : ERROR_TTL)
      entry
    rescue StandardError => e
      # A credential we can't read (rotated encryption key, unknown agent type)
      # must not take the profile page down with it.
      Rails.logger.warn("[SubscriptionUsageService] #{credential.agent_type} usage unavailable: #{e.class}: #{e.message}")
      nil
    end

    def refetch?(cached)
      @force && cached[:fetched_at].to_time <= MIN_REFRESH_INTERVAL.ago
    end

    def adapter_for(credential)
      @adapter_resolver.call(credential.agent_type)
    end

    def cache_key(credential)
      "agent_subscription_usage/#{credential.id}/#{credential.updated_at.to_i}"
    end
  end
end
