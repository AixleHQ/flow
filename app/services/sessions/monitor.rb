# frozen_string_literal: true

module Sessions
  # The one mechanism that reads live sessions' terminals for the checks
  # (Sessions::Checks). Every pass (Activities::Workflow::MonitorSessionsActivity, on the
  # session_monitor_workflow schedule, every minute) visits each live workflow step:
  #
  #   1. it asks every check whether it applies to the session (`applies_to?`); a session
  #      no check applies to is not read at all;
  #   2. it asks the applicable checks which snapshot parts they need
  #      (Snapshot::Parts::REGISTRY);
  #   3. it reads the union of those parts with one exec (Snapshot.read);
  #   4. it hands the snapshot to the applicable checks in CHECKS order, until one stops;
  #   5. it writes what the checks keep between passes in one update (Checks::KeptState).
  #
  # The snapshot is thrown away after the visit. The pass is one sweep, and the schedule's
  # `overlap: skip` drops the next pass while one still runs, so a slow pass stretches the
  # time between reads; each pass logs its duration and the number of sessions it read, so
  # that is visible.
  #
  # .snapshot reads one session on demand, through the same path and registry, for a caller
  # that cannot use a pass's minute-old view (the token-refresh sweep, decision 12 of #211).
  class Monitor
    # The order is the order of precedence: a session that cannot go on (quota, a dialog
    # nobody will answer) is failed before anything waits on it, a refused login is paused
    # before a turn end is reminded, and silence is judged last, once nothing else has
    # taken the session over on this pass.
    CHECKS = [
      Checks::QuotaError,
      Checks::BlockingPrompt,
      Checks::AuthPause,
      Checks::TurnEnd,
      Checks::NoOutput
    ].freeze

    COUNTED = { failed: :cleaned, paused: :auth_paused, nudged: :nudged }.freeze

    # The sessions any check can apply to; each check narrows them in its applies_to?.
    def self.candidates
      TerminalSession
        .where(state: Checks::Base::ACTIVE_STATES, session_type: :workflow_step)
        .where.not(container_id: [ nil, "" ])
    end

    def self.snapshot(session, parts:, runtime: nil)
      runtime ||= ContainerRuntime.for_session(session, op_timeout: Settings.runners.scan_op_timeout)
      Snapshot.read(session, parts: parts, runtime: runtime)
    end

    def initialize(checks: CHECKS)
      @checks = checks
    end

    # @return [Hash] the pass's counts: cleaned (failed), auth_paused, nudged, unreachable,
    #   read (sessions read) and duration_ms
    def pass
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      counts = { cleaned: 0, unreachable: 0, auth_paused: 0, nudged: 0, read: 0 }

      self.class.candidates.find_each do |session|
        visit(session, counts)
      rescue ContainerRuntime::ContainerUnreachableError => e
        # The pod behind this session is gone (node died, pod evicted). Its tmux is not
        # coming back, so reading it again every pass only burns CPU; the dead-container
        # watchdog decides its fate. One line per session, not one per exec attempt.
        Rails.logger.warn("[Sessions::Monitor] session=#{session.id} skipped: #{e.message}")
        counts[:unreachable] += 1
      rescue StandardError => e
        Rails.logger.warn("[Sessions::Monitor] session=#{session.id} failed to process: #{e.class}: #{e.message}")
      end

      counts[:duration_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      Rails.logger.info("[Sessions::Monitor] pass read=#{counts[:read]} duration_ms=#{counts[:duration_ms]} " \
                        "failed=#{counts[:cleaned]} auth_paused=#{counts[:auth_paused]} nudged=#{counts[:nudged]} " \
                        "unreachable=#{counts[:unreachable]}")
      counts
    end

    # One session: read once, run the applicable checks, keep what they keep.
    # @return [Array<Checks::Result>] what each check that ran answered
    def visit(session, counts = Hash.new(0))
      applicable = @checks.select { |check| check.applies_to?(session) }
      return [] if applicable.empty?

      # A runner session's ops are capped, so a machine that does not answer cannot hold
      # up the pass.
      runtime = ContainerRuntime.for_session(session, op_timeout: Settings.runners.scan_op_timeout)
      snapshot = self.class.snapshot(session, parts: applicable.flat_map(&:parts).uniq, runtime: runtime)
      counts[:read] += 1

      kept = Checks::KeptState.new(session)
      results = []
      begin
        applicable.each do |check|
          result = check.new(session, runtime: runtime, kept: kept.for(check)).call(snapshot)
          results << result
          counter = COUNTED[result.outcome]
          counts[counter] += 1 if counter
          break if result.stop?
        end
      ensure
        kept.write!
      end
      results
    end
  end
end
