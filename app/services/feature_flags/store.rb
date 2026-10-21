# frozen_string_literal: true

module FeatureFlags
  # The database-backed runtime values, held per process as one frozen Snapshot.
  # A check reads the held snapshot: no query and no Redis call. The request that
  # finds the refresh interval expired reads the version token once and reloads
  # only if it changed; after max staleness it reloads whatever the token says,
  # which covers Redis being down or the key evicted. No timer thread.
  #
  # A failed reload keeps the last good snapshot, so a flag never flips because
  # of an outage; with none loaded yet it is Snapshot::EMPTY, so ENV and the
  # declared defaults decide. Either way the next interval tries again.
  class Store
    MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def initialize(version_token:, refresh_interval:, max_staleness:,
                   loader: -> { FeatureFlag.load_snapshot }, clock: MONOTONIC_CLOCK)
      @version_token = version_token
      @refresh_interval = refresh_interval
      @max_staleness = max_staleness
      @loader = loader
      @clock = clock
      @snapshot = Concurrent::AtomicReference.new
      @refresh_lock = Mutex.new
      @next_check_at = nil
      @loaded_at = nil
      @token = nil
    end

    def snapshot
      refresh if refresh_due?
      @snapshot.get || Snapshot::EMPTY
    end

    private

    def refresh_due? = @next_check_at.nil? || @clock.call >= @next_check_at

    # One thread refreshes; any other that finds it due meanwhile serves the
    # snapshot it already has instead of queueing behind a database round trip.
    def refresh
      return unless @refresh_lock.try_lock

      begin
        now = @clock.call
        return unless @next_check_at.nil? || now >= @next_check_at

        @next_check_at = now + @refresh_interval
        # Read before the SELECTs: a write committed while they run then leaves
        # a token this store has not seen, and the next check reloads again.
        token = @version_token.read
        reload(token, now) if stale?(token, now)
      ensure
        @refresh_lock.unlock
      end
    end

    def stale?(token, now)
      @loaded_at.nil? || now >= @loaded_at + @max_staleness || (!token.nil? && token != @token)
    end

    def reload(token, now)
      @snapshot.set(@loader.call)
      @token = token
      @loaded_at = now
    rescue StandardError => e
      Rails.logger.error("[FeatureFlags] reload failed, serving the last loaded values: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, severity: :error, source: RELOAD_FAILED_SOURCE,
                            context: { error_class: e.class.name, loaded: !@snapshot.get.nil? })
    end
  end
end
