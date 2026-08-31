# frozen_string_literal: true

module Coder
  # DeadWorkspaceReaper — deletes pool workspaces whose agent is never coming
  # back.
  #
  # The pool runs on EC2 spot. When an instance is reclaimed, the interruption
  # handler halts the box and tells Coder nothing, and the agent is a cloud-init
  # child rather than a service, so it does not come back on a reboot either.
  # What Coder is left holding is a workspace whose LAST BUILD is still a
  # succeeded `start` — status "running", by the only definition the API has —
  # with every agent on it reporting `disconnected`. Nothing in this codebase
  # ever restarted or recycled such a workspace, so it stayed in the pool
  # forever and the effective pool decayed with the interruption rate. This is
  # the background process that closes that loop.
  #
  # Deleting a workspace is irreversible, so the bar for "it is dead" is set
  # deliberately high. All five must hold, and the last one twice:
  #
  #   1. Coder's own last build for it is a SUCCEEDED START. A stopped, deleting
  #      or mid-build workspace has no agent by design and is never a candidate
  #      — getting this wrong would delete the pool every time it is scaled down.
  #   2. Every agent on it explicitly reports `disconnected`/`timeout`
  #      (`HealthCheck.agents_unhealthy?`). Per § D-0 absence of agent data is
  #      never evidence: a workspace that reports no agents at all is left alone.
  #   3. No live lock is held on it. A session's box is never reaped underneath
  #      it, whatever Coder thinks of its agent.
  #   4. An SSH probe fails to REACH it. An overloaded box also probes `sick`,
  #      and it answered — it is alive and stays. A probe that fails on OUR side
  #      (no `coder` CLI, auth) resolves to `:unknown` and blocks the deletion,
  #      which is also why disabling `health_probe_enabled` disables reaping.
  #   5. All of the above held once before, at least `confirmation_minutes` ago.
  #      One sighting is a snapshot; two, spaced apart, with anything alive in
  #      between clearing the marker, is a diagnosis. Same doctrine as
  #      `Activities::Session::ScanDeadContainersActivity`.
  #
  # Blast radius is bounded on top of that by `max_deletions_per_run`: the
  # failure mode that matters is a fault on our side reading as a dead pool, and
  # a cap turns "deleted everything" into "deleted a few, and said so".
  #
  # First sightings are recorded in `integration_data` as
  # `coder:workspace_dead:<workspace_name>` — same table, TTL semantics and
  # `(integration_id, key)` isolation as the lock and quarantine markers.
  class DeadWorkspaceReaper
    MARKER_KEY_PREFIX = "coder:workspace_dead:"

    # Marker rows are pruned actively (a workspace that recovers or leaves the
    # pool drops its marker), so the TTL is only a backstop against rows this
    # service never gets to look at again — an integration that is deleted, a
    # prefix that changes.
    MARKER_TTL = 24.hours

    DEFAULT_CONFIRMATION_MINUTES = 10
    DEFAULT_MAX_DELETIONS        = 3

    class << self
      # Sweeps every active Coder integration. One integration failing (expired
      # token, Coder unreachable) must not stop the others, so its error is
      # logged and counted rather than raised.
      def reap_all
        totals = { integrations: 0, checked: 0, marked: 0, cleared: 0, deleted: 0, skipped: 0, errors: 0 }

        integrations.find_each do |integration|
          result = new(integration).reap
          totals[:integrations] += 1
          %i[checked marked cleared deleted skipped].each { |k| totals[k] += result[k].to_i }
          totals[:errors] += result[:failures].size
        rescue StandardError => e
          totals[:errors] += 1
          Rails.logger.warn("[Coder::DeadWorkspaceReaper] integration #{integration.id} failed: #{e.message}")
        end

        totals
      end

      def integrations
        Integration.where(provider: :coder, status: :active)
      end
    end

    def initialize(integration, workspace_service: nil, lock_service: nil,
                   health_check: nil, quarantine_service: nil)
      @integration        = integration
      @workspace_service  = workspace_service  || Coder::WorkspaceService.new(integration)
      @lock_service       = lock_service       || Coder::LockService.new(integration)
      @health_check       = health_check       || Coder::HealthCheck.new(integration)
      @quarantine_service = quarantine_service || Coder::QuarantineService.new(integration)
    end

    # Returns a tally of what the sweep did:
    # `{ checked:, marked:, cleared:, deleted:, skipped:, deleted_names:, failures: }`.
    def reap
      @checked  = 0
      @marked   = []
      @cleared  = []
      @deleted  = []
      @skipped  = []
      @failures = []

      return tally(enabled: false) unless enabled?

      workspaces = @workspace_service.list(prefix: prefix)
      prune_orphan_markers(workspaces.map { |w| w["name"].to_s })
      workspaces.each { |ws| consider(ws) }

      log_outcome
      tally
    end

    private

    def consider(workspace)
      name = workspace["name"].to_s
      id   = workspace["id"].to_s
      return if name.empty? || id.empty?

      @checked += 1

      if failed?(workspace)
        return delete_failed_workspace(name: name, id: id)
      end

      # A workspace that is stopped, being deleted, or mid-build is not a
      # workspace with a dead agent — it is one that is doing what it was told.
      return clear_marker(name) unless supposedly_running?(workspace)

      return clear_marker(name) unless Coder::HealthCheck.agents_unhealthy?(workspace)

      if @lock_service.held?(workspace_name: name)
        @skipped << "#{name} (held by a live session)"
        return
      end

      verdict = @health_check.probe(workspace_name: name)

      if verdict.reachable?
        # Coder says the agent is gone but the box answered a shell. Whatever is
        # wrong with it, it is not dead, and the allocator's quarantine already
        # handles a sick-but-alive machine.
        @skipped << "#{name} (agent reported dead, but the workspace answered a probe)"
        return clear_marker(name)
      end

      unless verdict.unreachable?
        @skipped << "#{name} (could not be confirmed dead: #{verdict.reason})"
        return
      end

      confirm_or_delete(name: name, id: id, reason: "#{Coder::HealthCheck.unhealthy_reason(workspace)}; #{verdict.reason}")
    end

    def supposedly_running?(workspace)
      workspace.dig("latest_build", "transition").to_s == "start" &&
        workspace.dig("latest_build", "job", "status").to_s == "succeeded"
    end

    def failed?(workspace)
      workspace.dig("latest_build", "job", "status").to_s == "failed"
    end

    # A failed provisioner build cannot recover by probing the agent, and a
    # failed delete build must not leave the workspace stuck forever. Try the
    # normal destroy first so Terraform can release its resources; if either
    # creating or completing that build fails, orphan the workspace record.
    def delete_failed_workspace(name:, id:)
      build = @workspace_service.delete(id)
      @workspace_service.await_build(build.fetch("id"))
      record_failed_workspace_deletion(name, orphan: false)
    rescue Coder::WorkspaceService::OperationError, KeyError => e
      Rails.logger.warn("[Coder::DeadWorkspaceReaper] normal delete #{name} failed: #{e.message}; retrying orphaned")
      begin
        orphan_build = @workspace_service.delete(id, orphan: true)
        @workspace_service.await_build(orphan_build.fetch("id"))
        record_failed_workspace_deletion(name, orphan: true)
      rescue Coder::WorkspaceService::OperationError, KeyError => orphan_error
        @failures << "#{name} (normal delete: #{e.message}; orphan delete: #{orphan_error.message})"
        Rails.logger.warn("[Coder::DeadWorkspaceReaper] orphan delete #{name} failed: #{orphan_error.message}")
      end
    end

    def record_failed_workspace_deletion(name, orphan:)
      clear_marker(name)
      @quarantine_service.clear(workspace_name: name)
      @deleted << name
      Rails.logger.info("[Coder::DeadWorkspaceReaper] deleted failed workspace #{name}#{' (orphaned)' if orphan}")
    end

    # First sighting only writes the marker. Deletion happens on a later sweep,
    # once `confirmation_minutes` have passed and the workspace still looks
    # exactly as dead as it did then.
    def confirm_or_delete(name:, id:, reason:)
      first_seen = marker_at(name)

      if first_seen.nil?
        write_marker(name, reason)
        @marked << name
        return
      end

      return if first_seen > confirmation_minutes.minutes.ago

      if @deleted.size >= max_deletions_per_run
        @skipped << "#{name} (per-run deletion cap of #{max_deletions_per_run} reached)"
        return
      end

      delete_workspace(name: name, id: id, reason: reason, dead_since: first_seen)
    end

    # The delete build runs asynchronously and we deliberately do not await it:
    # the next sweep sees `transition: "delete"` and skips the workspace, and a
    # build that fails outright leaves it as a succeeded start again, which the
    # sweep after that re-diagnoses from scratch.
    def delete_workspace(name:, id:, reason:, dead_since:)
      @workspace_service.delete(id)
      clear_marker(name)
      @quarantine_service.clear(workspace_name: name)
      @deleted << name
      Rails.logger.info(
        "[Coder::DeadWorkspaceReaper] deleted #{name} — dead since #{dead_since.iso8601}, confirmed twice (#{reason})"
      )
    rescue Coder::WorkspaceService::OperationError => e
      # Marker stays: the next sweep retries immediately instead of restarting
      # the confirmation window.
      @failures << "#{name} (#{e.message})"
      Rails.logger.warn("[Coder::DeadWorkspaceReaper] delete #{name} failed: #{e.message}")
    end

    # ----- markers -----

    def marker_at(name)
      row = markers.live.find_by(key: marker_key(name))
      return nil if row.nil?

      Time.zone.parse(row.value["first_seen_at"].to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def write_marker(name, reason)
      row = @integration.integration_data.find_or_initialize_by(key: marker_key(name))
      row.value = {
        "kind"          => "workspace_dead",
        "reason"        => reason.to_s,
        "first_seen_at" => Time.current.iso8601
      }
      row.expires_at = Time.current + MARKER_TTL
      row.save!
      Rails.logger.info("[Coder::DeadWorkspaceReaper] #{name} looks dead (#{reason}); re-checking in #{confirmation_minutes}m")
      row
    end

    def clear_marker(name)
      deleted = markers.where(key: marker_key(name)).delete_all
      @cleared << name if deleted.positive?
      nil
    end

    # A marker whose workspace is no longer in the pool (deleted by hand, prefix
    # changed) has nothing left to confirm.
    def prune_orphan_markers(live_names)
      keys = live_names.reject(&:empty?).map { |name| marker_key(name) }
      scope = markers
      scope = scope.where.not(key: keys) if keys.any?
      scope.delete_all
    end

    def markers
      @integration.integration_data.with_key_prefix(MARKER_KEY_PREFIX)
    end

    def marker_key(name)
      "#{MARKER_KEY_PREFIX}#{name}"
    end

    # ----- config + reporting -----

    def enabled?
      Settings.coder&.reap_enabled != false
    end

    def confirmation_minutes
      minutes = (Settings.coder&.reap_confirmation_minutes || DEFAULT_CONFIRMATION_MINUTES).to_i
      minutes.positive? ? minutes : DEFAULT_CONFIRMATION_MINUTES
    end

    def max_deletions_per_run
      max = (Settings.coder&.reap_max_deletions_per_run || DEFAULT_MAX_DELETIONS).to_i
      max.positive? ? max : DEFAULT_MAX_DELETIONS
    end

    def prefix
      @integration.coder_machine_prefix.presence
    end

    def log_outcome
      return if @deleted.empty? && @marked.empty? && @skipped.empty? && @failures.empty?

      parts = []
      parts << "deleted #{@deleted.join(', ')}" if @deleted.any?
      parts << "marked #{@marked.join(', ')}" if @marked.any?
      parts << "skipped #{@skipped.join('; ')}" if @skipped.any?
      parts << "failed #{@failures.join('; ')}" if @failures.any?
      Rails.logger.info("[Coder::DeadWorkspaceReaper] integration #{@integration.id}: #{parts.join(' | ')}")
    end

    def tally(enabled: true)
      {
        enabled:       enabled,
        checked:       @checked,
        marked:        @marked.size,
        cleared:       @cleared.size,
        deleted:       @deleted.size,
        skipped:       @skipped.size,
        deleted_names: @deleted.dup,
        failures:      @failures.dup
      }
    end
  end
end
