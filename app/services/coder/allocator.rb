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
  # Returns a plain hash describing the allocated workspace:
  #
  #   {
  #     workspace_id:      "uuid",
  #     workspace_name:    "aixle-prod-001",
  #     status:            "running" | "starting",
  #     coder_url:         "https://coder.example.com",
  #     ssh_command:       "coder ssh aixle-prod-001",
  #     lock_expires_at:   "2026-06-20T10:50:00Z"
  #   }
  class Allocator
    class ExhaustedError < StandardError; end

    def initialize(integration:, terminal_session:, workspace_service: nil, lock_service: nil)
      @integration       = integration
      @terminal_session  = terminal_session
      @workspace_service = workspace_service || Coder::WorkspaceService.new(integration)
      @lock_service      = lock_service      || Coder::LockService.new(integration)
    end

    def allocate(note: nil, acquired_by: nil)
      candidates = @workspace_service.list(prefix: prefix).sort_by do |w|
        status = w["latest_build"]&.dig("transition") == "start" && w.dig("latest_build", "job", "status") == "succeeded" ? 0 : 1
        [ status, w["name"].to_s ]
      end

      held           = []
      start_failures = []

      candidates.each do |ws|
        ws_name = ws["name"].to_s
        ws_id   = ws["id"].to_s
        next if ws_name.empty? || ws_id.empty?

        begin
          lock = @lock_service.acquire(
            workspace_name:      ws_name,
            workspace_id:        ws_id,
            terminal_session_id: @terminal_session.id,
            note:                note,
            acquired_by:         acquired_by
          )
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
          @lock_service.release_owned(
            workspace_name:      ws_name,
            terminal_session_id: @terminal_session.id
          )
          start_failures << "#{ws_name} (#{e.message})"
          next
        end

        return build_result(workspace_id: ws_id, workspace_name: ws_name, status: status, lock: lock)
      end

      if @integration.coder_default_template.present?
        created = create_new_workspace
        ws_id   = created["id"].to_s
        ws_name = created["name"].to_s
        lock    = @lock_service.acquire(
          workspace_name:      ws_name,
          workspace_id:        ws_id,
          terminal_session_id: @terminal_session.id,
          note:                note,
          acquired_by:         acquired_by
        )
        return build_result(workspace_id: ws_id, workspace_name: ws_name, status: "starting", lock: lock)
      end

      raise ExhaustedError, exhausted_message(
        candidates: candidates, held: held, start_failures: start_failures
      )
    end

    private

    # Reaching this point means every candidate was unusable AND no default
    # template is configured (a configured one either returns a workspace or
    # raises its own `OperationError`). The old single sentence claimed "no
    # workspaces available" for all of those, which read as an empty pool even
    # when the pool was full and merely locked — so spell out which it was.
    def exhausted_message(candidates:, held:, start_failures:)
      pool =
        if candidates.empty?
          prefix ? "no workspaces match prefix #{prefix.inspect}" : "the Coder account has no workspaces"
        else
          reasons = []
          reasons << "#{held.size} held by other sessions (#{held.join(', ')})" if held.any?
          reasons << "#{start_failures.size} failed to start: #{start_failures.join('; ')}" if start_failures.any?
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
