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
      @check_at = nil
      @reload_at = nil
      @token = nil
    end

    def snapshot
      refresh if due?(@clock.call)
      @snapshot.get || Snapshot::EMPTY
    end

    private

    def due?(now) = check_due?(now) || reload_due?(now)
    def check_due?(now) = @check_at.nil? || now >= @check_at
    def reload_due?(now) = @reload_at.nil? || now >= @reload_at

    # One thread refreshes; any other that finds it due meanwhile serves the
    # snapshot it already has instead of queueing behind a database round trip.
    def refresh
      return unless @refresh_lock.try_lock

      begin
        now = @clock.call
        check = check_due?(now)
        forced = reload_due?(now)
        return unless check || forced

        token = @token
        if check
          @check_at = now + @refresh_interval
          # Read before the SELECTs: a write committed while they run then
          # leaves a token this store has not seen, and the next check reloads.
          token = @version_token.read
        end
        reload(token, now) if forced || (!token.nil? && token != @token)
      ensure
        @refresh_lock.unlock
      end
    end

    def reload(token, now)
      @snapshot.set(@loader.call)
      @token = token
      @reload_at = now + @max_staleness
    rescue StandardError => e
      # A token change that failed to load is retried by the next check, as the
      # token still differs; a forced reload is retried after one interval.
      @reload_at = now + @refresh_interval if reload_due?(now)
      Rails.logger.error("[FeatureFlags] reload failed, serving the last loaded values: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, severity: :error, source: RELOAD_FAILED_SOURCE,
                            context: { error_class: e.class.name, loaded: !@snapshot.get.nil? })
    end
  end
end
