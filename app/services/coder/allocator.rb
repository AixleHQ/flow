# frozen_string_literal: true

module Coder
  # Allocator — lock-first workspace allocation for a Coder integration.
  #
  # Lists candidate workspaces by the integration's configured prefix, sorts
  # running ones first, then attempts to acquire the lock for each candidate
  # in turn. If all candidates are held by other sessions, falls through to
  # creating a new workspace (when the integration is configured with a
  # default template).
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
  # Returns a plain hash describing the allocated workspace:
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

    # Fallback ordering when every candidate failed a health check: a box that
    # merely looks loaded beats one under an unexpired quarantine, which beats
    # one whose agent Coder itself reports as disconnected.
    RANK_PROBE_REJECTED = 0
    RANK_QUARANTINED    = 1
    RANK_AGENT_UNHEALTHY = 2

    def initialize(integration:, terminal_session:, workspace_service: nil, lock_service: nil,
                   quarantine_service: nil, health_check: nil)
      @integration        = integration
      @terminal_session   = terminal_session
      @workspace_service  = workspace_service  || Coder::WorkspaceService.new(integration)
      @lock_service       = lock_service       || Coder::LockService.new(integration)
      @quarantine_service = quarantine_service || Coder::QuarantineService.new(integration)
      @health_check       = health_check       || Coder::HealthCheck.new(integration)
    end

    def allocate(note: nil, acquired_by: nil, exclude: [])
      excluded = Array(exclude).map(&:to_s).map(&:strip).reject(&:empty?)

      candidates = @workspace_service.list(prefix: prefix).sort_by do |w|
        status = w["latest_build"]&.dig("transition") == "start" && w.dig("latest_build", "job", "status") == "succeeded" ? 0 : 1
        [ status, w["name"].to_s ]
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
          status = ensure_started(ws)
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

        return build_result(workspace_id: ws_id, workspace_name: ws_name, status: status, lock: lock)
      end

      if @integration.coder_default_template.present?
        created = create_workspace_or_nil(note: note, acquired_by: acquired_by)
        return created if created
      end

      fallback = allocate_deferred(deferred, note: note, acquired_by: acquired_by)
      return fallback if fallback

      raise ExhaustedError, exhausted_message(
        candidates: candidates, held: held, start_failures: start_failures,
        skipped: skipped, deferred: deferred
      )
    end

    private

    def acquire_lock(ws_name, ws_id, note:, acquired_by:)
      @lock_service.acquire(
        workspace_name:      ws_name,
        workspace_id:        ws_id,
        terminal_session_id: @terminal_session.id,
        note:                note,
        acquired_by:         acquired_by
      )
    end

    def release_own_lock(ws_name)
      @lock_service.release_owned(
        workspace_name:      ws_name,
        terminal_session_id: @terminal_session.id
      )
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

    def create_workspace_or_nil(note:, acquired_by:)
      created = create_new_workspace
      ws_id   = created["id"].to_s
      ws_name = created["name"].to_s
      lock    = acquire_lock(ws_name, ws_id, note: note, acquired_by: acquired_by)

      build_result(workspace_id: ws_id, workspace_name: ws_name, status: "starting", lock: lock)
    rescue Coder::WorkspaceService::OperationError => e
      # Creation is the preferred escape from an unhealthy pool, but it is not
      # the last one: fall through to the deferred candidates instead of
      # failing the allocation outright.
      Rails.logger.warn("[Coder::Allocator] create_workspace failed: #{e.message}")
      nil
    end

    # Reaching this point means every candidate was unusable AND no default
    # template is configured (a configured one either returns a workspace or
    # raises its own `OperationError`). The old single sentence claimed "no
    # workspaces available" for all of those, which read as an empty pool even
    # when the pool was full and merely locked — so spell out which it was.
    def exhausted_message(candidates:, held:, start_failures:, skipped: [], deferred: [])
      pool =
        if candidates.empty?
          prefix ? "no workspaces match prefix #{prefix.inspect}" : "the Coder account has no workspaces"
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

      "#{pool}; no default_template configured on the integration, so the pool cannot grow"
    end

    def prefix
      @integration.coder_machine_prefix.presence
    end

    def ensure_started(workspace)
      status = workspace.dig("latest_build", "job", "status").to_s
      transition = workspace.dig("latest_build", "transition").to_s
      return "running" if transition == "start" && status == "succeeded"

      # If a start-build is already in flight (e.g. left over from a previous
      # allocation attempt that timed out at the MCP layer), await that build
      # instead of triggering a new one — issuing another `start` against the
      # same workspace would race the existing build and return HTTP 409.
      if transition == "start" && %w[pending running].include?(status)
        build_id = workspace.dig("latest_build", "id").to_s
        @workspace_service.await_build(build_id) if build_id.present?
        return "running"
      end

      build = @workspace_service.start(workspace["id"])
      @workspace_service.await_build(build["id"])
      "running"
    end

    def create_new_workspace
      name = generate_workspace_name
      created = @workspace_service.create_workspace(
        name:          name,
        template_name: @integration.coder_default_template
      )
      build_id = created.dig("latest_build", "id")
      @workspace_service.await_build(build_id) if build_id.present?
      created
    end

    def generate_workspace_name
      "#{prefix || 'aixle'}-#{SecureRandom.hex(4)}"
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
