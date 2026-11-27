# frozen_string_literal: true

module Coder
  # Allocator — lock-first workspace allocation for a Coder integration.
  #
  # Lists the workspaces the integration's token owns under its configured
  # prefix, sorts running ones first, then attempts to acquire the lock for
  # each candidate in turn. If all candidates are held by other sessions,
  # falls through to creating a new workspace (when the integration is
  # configured with a default template).
  #
  # Health gating (see `Coder::HealthCheck`) sits on top of that: a candidate
  # the Coder agent reports as broken, or one under quarantine from a recent
  # failed probe, is passed over; the workspace that does get the lock is
  # probed over SSH before it is handed to the session. `status: "running"` is
  # about the last BUILD, never about whether the box can still do work — that
  # gap is what handed the same saturated machine to four consecutive
  # allocations.
  #
  # The degradation contract (§ D-0) constrains all of it: rejection needs
  # positive evidence, and if every candidate is rejected on health the
  # allocator hands back the least-bad one with a `health_warning` rather than
  # failing while usable boxes exist. Allocation must never be worse than it
  # was before health gating existed.
  #
  # The holder is a `Coder::LockService::Holder`: a terminal session (the
  # agents' `coder_*` tools) or a runner environment. A session's hold expires
  # with its inactivity; an environment's is explicit, ends only through
  # `delete` or `LockService#release_owned`, and is never taken by another
  # holder, never reaped and never reclaimed.
  #
  # `allocate(wait: false)` is for a caller that cannot sit in a build: it never
  # sleeps in `await_build` and returns a `Result`, `:ready` or `:pending`, and
  # every retry for the same holder continues the same workspace. It hands a
  # workspace over only when it is ready, as the integration defines it: the
  # build succeeded, the agent is connected and the SSH probe passed. A
  # workspace that fails the probe is quarantined and released, as in the
  # blocking mode, and is never handed over, including as the blocking mode's
  # least-bad fallback.
  #
  # With `wait: true` (the default) it returns a plain hash describing the
  # allocated workspace:
  #
  #   {
  #     workspace_id:      "uuid",
  #     workspace_name:    "aixle-prod-001",
  #     status:            "running" | "starting",
  #     coder_url:         "https://coder.example.com",
  #     ssh_command:       "coder ssh aixle-prod-001",
  #     lock_expires_at:   "2026-06-20T10:50:00Z",
  #     health_warning:    "..."   # only when nothing healthy was available
  #   }
  class Allocator
    class ExhaustedError < StandardError; end

    # What `allocate(wait: false)` answers: `:ready` with the workspace hash
    # (the same one the blocking mode returns), or `:pending` with the
    # workspace the holder holds and what it is waiting for.
    Result = Data.define(:status, :workspace, :message) do
      def ready?   = status == :ready
      def pending? = status == :pending
    end

    # Fallback ordering when every candidate failed a health check: a box that
    # merely looks loaded beats one under an unexpired quarantine, which beats
    # one whose agent Coder itself reports as disconnected.
    RANK_PROBE_REJECTED = 0
    RANK_QUARANTINED    = 1
    RANK_AGENT_UNHEALTHY = 2

    def initialize(integration:, holder:, workspace_service: nil, lock_service: nil,
                   quarantine_service: nil, health_check: nil)
      @integration        = integration
      @holder             = holder
      @workspace_service  = workspace_service  || Coder::WorkspaceService.new(integration)
      @lock_service       = lock_service       || Coder::LockService.new(integration)
      @quarantine_service = quarantine_service || Coder::QuarantineService.new(integration)
      @health_check       = health_check       || Coder::HealthCheck.new(integration)
    end

    def allocate(note: nil, acquired_by: nil, exclude: [], wait: true)
      excluded = Array(exclude).map(&:to_s).map(&:strip).reject(&:empty?)

      unless wait
        held = @lock_service.held_by(holder: @holder)
        if held
          continued = continue_hold(held)
          return continued if continued
        end
      end

      candidates = @workspace_service.list(prefix: prefix, own: true).sort_by do |w|
        [ Coder::WorkspaceStatus.from(w).running? ? 0 : 1, w["name"].to_s ]
      end

      held           = []
      start_failures = []
      skipped        = []
      deferred       = []

      candidates.each do |ws|
        ws_name = ws["name"].to_s
        ws_id   = ws["id"].to_s
        next if ws_name.empty? || ws_id.empty?

        if excluded.include?(ws_name)
          skipped << "#{ws_name} (excluded by caller)"
          next
        end

        if @quarantine_service.quarantined?(workspace_name: ws_name)
          deferred << { ws: ws, name: ws_name, id: ws_id, rank: RANK_QUARANTINED,
                        reason: quarantine_reason(ws_name) }
          next
        end

        if Coder::HealthCheck.agents_unhealthy?(ws)
          deferred << { ws: ws, name: ws_name, id: ws_id, rank: RANK_AGENT_UNHEALTHY,
                        reason: Coder::HealthCheck.unhealthy_reason(ws) }
          next
        end

        begin
          lock = acquire_lock(ws_name, ws_id, note: note, acquired_by: acquired_by)
        rescue Coder::LockService::LockNotAcquired
          held << ws_name
          next
        end

        begin
          if wait
            status = ensure_started(ws)
          else
            waiting_for = advance(ws_name, ws, Coder::WorkspaceStatus.from(ws), retrying: false)
            return pending_result(waiting_for, workspace_id: ws_id, workspace_name: ws_name, lock: lock) if waiting_for

            status = "running"
          end
        rescue Coder::WorkspaceService::OperationError => e
          # A lock is only worth holding while the workspace is usable. Handing
          # it back keeps a failed start (spot capacity, build timeout) from
          # stranding the machine for the whole lock TTL, which is what turned
          # a transient EC2 hiccup into an exhausted pool. Holder-scoped, so a
          # session that reclaimed an expired lock underneath us keeps it.
          release_own_lock(ws_name)
          start_failures << "#{ws_name} (#{e.message})"
          next
        end

        verdict = @health_check.probe(workspace_name: ws_name)
        if verdict.sick?
          @quarantine_service.quarantine(workspace_name: ws_name, reason: verdict.reason)
          release_own_lock(ws_name)
          deferred << { ws: ws, name: ws_name, id: ws_id, rank: RANK_PROBE_REJECTED,
                        reason: verdict.reason, load: verdict.load, status: status }
          next
        end

        @quarantine_service.clear(workspace_name: ws_name) if verdict.healthy?

        result = build_result(workspace_id: ws_id, workspace_name: ws_name, status: status, lock: lock)
        return wait ? result : Result.new(status: :ready, workspace: result, message: nil)
      end

      create_failure = nil
      if @integration.coder_default_template.present?
        begin
          return create_and_lock(note: note, acquired_by: acquired_by, wait: wait)
        rescue Coder::WorkspaceService::OperationError => e
          # Without waiting, only a quota refusal means "no capacity"; any other
          # refusal is a provisioning failure the caller must see as such.
          raise unless wait || e.is_a?(Coder::WorkspaceService::QuotaError)

          # Creation is the preferred escape from an unhealthy pool, but it is
          # not the last one: fall through to the deferred candidates instead
          # of failing the allocation outright.
          Rails.logger.warn("[Coder::Allocator] create_workspace failed: #{e.message}")
          create_failure = e.message
        end
      end

      # The least-bad fallback hands over a workspace that failed a health
      # check. A caller that asked not to wait is told only about a ready one.
      fallback = wait ? allocate_deferred(deferred, note: note, acquired_by: acquired_by) : nil
      return fallback if fallback

      raise ExhaustedError, exhausted_message(
        candidates: candidates, held: held, start_failures: start_failures,
        skipped: skipped, deferred: deferred, create_failure: create_failure
      )
    end

    # Deletes the workspace `holder` holds, through the integration, and
    # releases the hold once Coder reports it deleted. `:pending` while the
    # delete build runs, `:gone` when it is done, and `:gone` at once for a
    # holder that holds nothing or a workspace Coder no longer knows. A delete
    # Coder refuses raises `WorkspaceService::OperationError`; the caller retries.
    #
    # The workspace is found by its hold, not by a name the caller recorded: one
    # locked before any name was written down is deleted too, never returned to
    # the pool.
    def delete(holder: @holder)
      hold = @lock_service.held_by(holder: holder)
      return :gone unless hold

      status = @workspace_service.status(hold.workspace_name)
      if status.deleted?
        @lock_service.release_owned(workspace_name: hold.workspace_name, holder: holder)
        return :gone
      end
      return :pending if status.deleting?

      @workspace_service.delete(hold.workspace_id)
      :pending
    end

    private

    def acquire_lock(ws_name, ws_id, note:, acquired_by:)
      @lock_service.acquire(
        workspace_name: ws_name,
        workspace_id:   ws_id,
        holder:         @holder,
        note:           note,
        acquired_by:    acquired_by
      )
    end

    def release_own_lock(ws_name)
      @lock_service.release_owned(workspace_name: ws_name, holder: @holder)
    end

    # The next try of a holder that already holds a workspace: continue that one
    # from where it stands. Returns a `Result`, or nil when the workspace failed
    # its probe (quarantined and released, so the search for another goes on).
    # A workspace that cannot be recovered raises `OperationError`.
    def continue_hold(hold)
      status = @workspace_service.status(hold.workspace_name)
      waiting_for = advance(hold.workspace_name, { "id" => hold.workspace_id }, status, retrying: true)
      if waiting_for
        return pending_result(waiting_for, workspace_id: hold.workspace_id, workspace_name: hold.workspace_name, lock: hold)
      end

      verdict = @health_check.probe(workspace_name: hold.workspace_name)
      if verdict.sick?
        @quarantine_service.quarantine(workspace_name: hold.workspace_name, reason: verdict.reason)
        release_own_lock(hold.workspace_name)
        return nil
      end

      @quarantine_service.clear(workspace_name: hold.workspace_name) if verdict.healthy?
      workspace = build_result(workspace_id: hold.workspace_id, workspace_name: hold.workspace_name,
                               status: "running", lock: hold)
      Result.new(status: :ready, workspace: workspace, message: nil)
    end

    # One non-blocking step of bringing a locked workspace up: starts it when it
    # is stopped, and says what it is waiting for otherwise. Returns nil when
    # the build succeeded and the agent is connected (the workspace is ready to
    # be probed), or the message of what it waits for.
    #
    # `retrying` is a holder continuing a workspace it held already: a build
    # that failed is then final. A candidate just locked from the pool gets a
    # new start instead, as the blocking mode gives it.
    def advance(ws_name, workspace, status, retrying:)
      case status.state
      when :deleted
        raise Coder::WorkspaceService::OperationError, "workspace #{ws_name} was deleted"
      when :deleting
        raise Coder::WorkspaceService::OperationError, "workspace #{ws_name} is being deleted"
      when :failed
        if retrying
          detail = status.error ? " — #{@workspace_service.redacted_excerpt(status.error)}" : ""
          raise Coder::WorkspaceService::OperationError,
                "build #{status.build_id} of workspace #{ws_name} failed (#{status.transition})#{detail}"
        end

        start_async(ws_name, workspace, status)
      when :stopped
        start_async(ws_name, workspace, status)
      when :building
        status.transition == "start" ? "Starting workspace #{ws_name}" : "Waiting for workspace #{ws_name} to stop"
      else
        status.connected? ? nil : "Waiting for the agent of #{ws_name}"
      end
    end

    def start_async(ws_name, workspace, status)
      @workspace_service.ensure_started_async(workspace, status: status)
      "Starting workspace #{ws_name}"
    end

    def pending_result(message, workspace_id:, workspace_name:, lock:)
      workspace = build_result(workspace_id: workspace_id, workspace_name: workspace_name,
                               status: "starting", lock: lock)
      Result.new(status: :pending, workspace: workspace, message: message)
    end

    def quarantine_reason(ws_name)
      @quarantine_service.reasons[ws_name].presence || "recently failed a health probe"
    end

    # Every candidate failed a health check. Raising here would be a regression
    # against the behaviour that predates health gating — the session would get
    # nothing where it used to get a workspace — so hand back the least-bad box
    # and say so. The quarantine row stays: this is a fallback, not a pardon.
    def allocate_deferred(deferred, note:, acquired_by:)
      return nil if deferred.empty?

      ordered = deferred.sort_by { |c| [ c[:rank], c[:load] || Float::INFINITY, c[:name] ] }

      ordered.each do |candidate|
        begin
          lock = acquire_lock(candidate[:name], candidate[:id], note: note, acquired_by: acquired_by)
        rescue Coder::LockService::LockNotAcquired
          next
        end

        begin
          status = candidate[:status] || ensure_started(candidate[:ws])
        rescue Coder::WorkspaceService::OperationError
          release_own_lock(candidate[:name])
          next
        end

        return build_result(
          workspace_id: candidate[:id], workspace_name: candidate[:name],
          status: status, lock: lock
        ).merge(
          health_warning: "no healthy workspace was available; allocated anyway — #{candidate[:reason]}"
        )
      end

      nil
    end

    def create_and_lock(note:, acquired_by:, wait: true)
      created = create_new_workspace(wait: wait)
      ws_id   = created["id"].to_s
      ws_name = created["name"].to_s
      lock    = acquire_lock(ws_name, ws_id, note: note, acquired_by: acquired_by)

      unless wait
        return pending_result("Building workspace #{ws_name}", workspace_id: ws_id, workspace_name: ws_name, lock: lock)
      end

      build_result(workspace_id: ws_id, workspace_name: ws_name, status: "starting", lock: lock)
    end

    # An empty pool, a full-but-locked one and a template that will not build
    # each need a different fix, so the message names which it was.
    # `create_failure` comes from an `OperationError`, which `WorkspaceService`
    # has already stripped of the session token.
    def exhausted_message(candidates:, held:, start_failures:, skipped: [], deferred: [], create_failure: nil)
      pool =
        if candidates.empty?
          owned = "the token's Coder account owns no workspaces"
          prefix ? "#{owned} matching prefix #{prefix.inspect}" : owned
        else
          reasons = []
          reasons << "#{held.size} held by other sessions (#{held.join(', ')})" if held.any?
          reasons << "#{start_failures.size} failed to start: #{start_failures.join('; ')}" if start_failures.any?
          reasons << "#{skipped.size} skipped: #{skipped.join('; ')}" if skipped.any?
          if deferred.any?
            detail = deferred.map { |c| "#{c[:name]} (#{c[:reason]})" }.join("; ")
            reasons << "#{deferred.size} unhealthy and unlockable: #{detail}"
          end
          "none of the #{candidates.size} workspaces in the pool could be allocated — #{reasons.join('; ')}"
        end

      growth =
        if create_failure
          "creating a workspace from template #{@integration.coder_default_template.inspect} failed: #{create_failure}"
        else
          "no default_template configured on the integration, so the pool cannot grow"
        end

      "#{pool}; #{growth}"
    end

    def prefix
      @integration.coder_machine_prefix.presence
    end

    # The blocking start: `ensure_started_async` (which reuses a start build
    # already in flight, e.g. one left over from an allocation attempt that
    # timed out at the MCP layer, since another `start` would race it and answer
    # HTTP 409), then wait for that build.
    def ensure_started(workspace)
      build = @workspace_service.ensure_started_async(workspace)
      @workspace_service.await_build(build["id"]) if build && build["id"].present?
      "running"
    end

    def create_new_workspace(wait: true)
      name = generate_workspace_name
      created = @workspace_service.create_workspace(
        name:          name,
        template_name: @integration.coder_default_template
      )
      build_id = created.dig("latest_build", "id")
      @workspace_service.await_build(build_id) if wait && build_id.present?
      created
    end

    def generate_workspace_name
      Coder::Pool.generate_name(prefix)
    end

    def build_result(workspace_id:, workspace_name:, status:, lock:)
      {
        workspace_id:    workspace_id,
        workspace_name:  workspace_name,
        status:          status,
        coder_url:       @integration.coder_url,
        ssh_command:     "coder ssh #{workspace_name}",
        lock_expires_at: lock&.expires_at&.iso8601
      }
    end
  end
end
