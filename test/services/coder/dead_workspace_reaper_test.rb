# frozen_string_literal: true

require "test_helper"

module Coder
  class DeadWorkspaceReaperTest < ActiveSupport::TestCase
    # Stands in for Coder::WorkspaceService (app-owned adapter, injected through
    # the constructor seam). Its own HTTP contract is covered in
    # workspace_service_test; here it only has to record deletions.
    class FakeWorkspaceService
      attr_reader :deleted_ids, :delete_calls

      def initialize(workspaces: [], failing_delete_ids: [], permanently_failing_delete_ids: [])
        @workspaces                     = workspaces
        @failing_delete_ids             = failing_delete_ids
        @permanently_failing_delete_ids = permanently_failing_delete_ids
        @deleted_ids                    = []
        @delete_calls                   = []
      end

      def list(prefix: nil)
        return @workspaces if prefix.blank?

        @workspaces.select { |w| w["name"].to_s.start_with?(prefix) }
      end

      def delete(workspace_id, orphan: false)
        @deleted_ids << workspace_id
        @delete_calls << [ workspace_id, orphan ]
        if @failing_delete_ids.include?(workspace_id) || @permanently_failing_delete_ids.include?(workspace_id)
          @failing_delete_ids.delete(workspace_id) if orphan == false
          raise Coder::WorkspaceService::OperationError, "build (delete) failed: HTTP 500"
        end

        { "id" => "build-del-#{workspace_id}", "transition" => "delete" }
      end

      def await_build(build_id)
        { "id" => build_id, "job" => { "status" => "succeeded" } }
      end
    end

    # Stands in for HealthCheck's active tier (its decision logic is covered in
    # health_check_test). Verdicts are keyed by workspace name.
    class FakeHealthCheck
      attr_reader :probed

      VERDICTS = {
        unreachable: { state: :sick,    reason: "did not answer a 15s probe", reachable: false },
        overloaded:  { state: :sick,    reason: "load average 84.3 over 4.0 (2 cores)", reachable: true },
        healthy:     { state: :healthy, reason: "load 0.1 on 2 cores", reachable: true },
        unknown:     { state: :unknown, reason: "coder CLI missing from the Rails image" }
      }.freeze

      def initialize(verdicts = {}, default: :unreachable)
        @verdicts = verdicts
        @default  = default
        @probed   = []
      end

      def probe(workspace_name:)
        @probed << workspace_name
        Coder::HealthCheck::Result.new(**VERDICTS.fetch(@verdicts.fetch(workspace_name, @default)))
      end
    end

    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @integration.update!(settings: @integration.settings.merge("machine_prefix" => "aixle-prod"))
    end

    # A workspace Coder still believes is running: its last build is a
    # succeeded start. That is the shape a spot-killed box keeps forever.
    def running(name, id, agents: [ { "status" => "disconnected" } ], transition: "start", status: "succeeded")
      {
        "id"           => id,
        "name"         => name,
        "latest_build" => {
          "transition" => transition,
          "job"        => { "status" => status },
          "resources"  => [ { "agents" => agents } ]
        }
      }
    end

    def build_reaper(workspace_service:, health_check: FakeHealthCheck.new, lock_service: nil)
      Coder::DeadWorkspaceReaper.new(
        @integration,
        workspace_service: workspace_service,
        health_check:      health_check,
        lock_service:      lock_service || Coder::LockService.new(@integration)
      )
    end

    def marker_key(name) = "coder:workspace_dead:#{name}"

    def marker_for(name)
      @integration.integration_data.find_by(key: marker_key(name))
    end

    # ---------- the happy path: two sightings, then deletion ----------

    test "a workspace confirmed dead twice is deleted on the second sighting" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      reaper  = build_reaper(workspace_service: service)

      first = reaper.reap

      assert_equal 1, first[:marked]
      assert_equal 0, first[:deleted]
      assert_empty service.deleted_ids
      assert marker_for("aixle-prod-1")

      travel 11.minutes do
        second = build_reaper(workspace_service: service).reap

        assert_equal 1, second[:deleted]
        assert_equal [ "aixle-prod-1" ], second[:deleted_names]
        assert_equal [ "u1" ], service.deleted_ids
        assert_nil marker_for("aixle-prod-1"), "the marker is dropped once the workspace is gone"
      end
    end

    test "a workspace whose latest build failed is deleted" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1", status: "failed") ])

      result = build_reaper(workspace_service: service).reap

      assert_equal 1, result[:deleted]
      assert_equal [ [ "u1", false ] ], service.delete_calls
    end

    test "a failed workspace falls back to orphan delete when normal delete is refused" do
      service = FakeWorkspaceService.new(
        workspaces: [ running("aixle-prod-1", "u1", status: "failed") ],
        failing_delete_ids: [ "u1" ]
      )

      result = build_reaper(workspace_service: service).reap

      assert_equal 1, result[:deleted]
      assert_empty result[:failures]
      assert_equal [ [ "u1", false ], [ "u1", true ] ], service.delete_calls
    end

    test "a failed workspace delete error does not stop the remaining workspaces" do
      service = FakeWorkspaceService.new(
        workspaces: [
          running("aixle-prod-1", "u1", status: "failed"),
          running("aixle-prod-2", "u2", status: "failed")
        ],
        permanently_failing_delete_ids: [ "u1" ]
      )

      result = build_reaper(workspace_service: service).reap

      assert_equal 1, result[:deleted]
      assert_equal 1, result[:failures].size
      assert_includes service.deleted_ids, "u2"
    end

    test "a workspace with a delete build in progress is untouched" do
      service = FakeWorkspaceService.new(workspaces: [
        running("aixle-prod-1", "u1", transition: "delete", status: "running")
      ])

      result = build_reaper(workspace_service: service).reap

      assert_equal 0, result[:deleted]
      assert_empty service.delete_calls
    end

    test "nothing is deleted while the confirmation window is still open" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      build_reaper(workspace_service: service).reap
      first_seen = marker_for("aixle-prod-1").value["first_seen_at"]

      travel 5.minutes do
        result = build_reaper(workspace_service: service).reap

        assert_equal 0, result[:deleted]
        assert_empty service.deleted_ids
        assert_equal first_seen, marker_for("aixle-prod-1").value["first_seen_at"],
                     "a repeat sighting must not push the confirmation window forward"
      end
    end

    test "deleting clears the workspace's quarantine marker too" do
      quarantine = Coder::QuarantineService.new(@integration)
      quarantine.quarantine(workspace_name: "aixle-prod-1", reason: "unresponsive")
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])

      build_reaper(workspace_service: service).reap
      travel(11.minutes) { build_reaper(workspace_service: service).reap }

      assert_not quarantine.quarantined?(workspace_name: "aixle-prod-1")
    end

    # ---------- what must never be deleted ----------

    test "a workspace whose agents are connected is left alone and loses its marker" do
      dead  = running("aixle-prod-1", "u1")
      alive = running("aixle-prod-1", "u1", agents: [ { "status" => "connected" } ])

      service = FakeWorkspaceService.new(workspaces: [ dead ])
      build_reaper(workspace_service: service).reap
      assert marker_for("aixle-prod-1")

      recovered = FakeWorkspaceService.new(workspaces: [ alive ])
      travel 11.minutes do
        result = build_reaper(workspace_service: recovered).reap

        assert_equal 0, result[:deleted]
        assert_equal 1, result[:cleared]
        assert_nil marker_for("aixle-prod-1"), "a recovered workspace restarts the confirmation from scratch"
      end
    end

    # § D-0: absence of a signal is never evidence.
    test "a workspace reporting no agent data at all is never a candidate" do
      service = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])
      health = FakeHealthCheck.new

      result = build_reaper(workspace_service: service, health_check: health).reap

      assert_equal 0, result[:marked]
      assert_empty health.probed, "an unprobed workspace cannot be confirmed dead"
      assert_nil marker_for("aixle-prod-1")
    end

    # The one that would delete the pool on every scale-down.
    test "a stopped or mid-build workspace is never a candidate" do
      service = FakeWorkspaceService.new(workspaces: [
        running("aixle-prod-1", "u1", transition: "stop"),
        running("aixle-prod-2", "u2", transition: "delete"),
        running("aixle-prod-3", "u3", status: "running"),
        running("aixle-prod-4", "u4", transition: "delete", status: "running")
      ])

      result = build_reaper(workspace_service: service).reap

      assert_equal 4, result[:checked]
      assert_equal 0, result[:marked]
      assert_empty service.deleted_ids
    end

    test "a workspace held by a live session is never reaped underneath it" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      locks   = Coder::LockService.new(@integration)
      locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", terminal_session_id: "sess-1")

      build_reaper(workspace_service: service, lock_service: locks).reap
      travel(11.minutes) { build_reaper(workspace_service: service, lock_service: locks).reap }

      assert_empty service.deleted_ids
      assert_nil marker_for("aixle-prod-1")
    end

    test "a box that answers the probe is alive however bad it looks" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health  = FakeHealthCheck.new({ "aixle-prod-1" => :overloaded })

      result = build_reaper(workspace_service: service, health_check: health).reap

      assert_equal 0, result[:marked]
      assert_equal 1, result[:skipped]
      assert_nil marker_for("aixle-prod-1")
    end

    # A fault on our side (no coder CLI, auth) must not read as a dead pool.
    test "a probe that could not run blocks the deletion instead of confirming it" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health  = FakeHealthCheck.new({}, default: :unknown)

      build_reaper(workspace_service: service, health_check: health).reap
      travel(11.minutes) { build_reaper(workspace_service: service, health_check: health).reap }

      assert_empty service.deleted_ids
      assert_nil marker_for("aixle-prod-1")
    end

    # ---------- blast radius ----------

    test "one sweep deletes at most the configured number of workspaces" do
      workspaces = (1..5).map { |n| running("aixle-prod-#{n}", "u#{n}") }
      service    = FakeWorkspaceService.new(workspaces: workspaces)

      build_reaper(workspace_service: service).reap

      travel 11.minutes do
        result = build_reaper(workspace_service: service).reap

        assert_equal 3, result[:deleted], "the per-run cap bounds what one bad diagnosis can remove"
        assert_equal 3, service.deleted_ids.size
        assert_equal 2, result[:skipped]
      end

      # The ones the cap held back keep their markers, so the next sweep takes
      # them without waiting out another confirmation window.
      travel 12.minutes do
        build_reaper(workspace_service: service).reap

        assert_equal 5, service.deleted_ids.uniq.size
      end
    end

    test "a failed delete keeps the marker so the next sweep retries at once" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ], failing_delete_ids: [ "u1" ])

      build_reaper(workspace_service: service).reap

      travel 11.minutes do
        result = build_reaper(workspace_service: service).reap

        assert_equal 0, result[:deleted]
        assert_equal 1, result[:failures].size
        assert marker_for("aixle-prod-1")
      end
    end

    # ---------- housekeeping ----------

    test "markers for workspaces that left the pool are pruned" do
      create(:integration_data, integration: @integration, key: marker_key("gone"),
                                value: { "kind" => "workspace_dead", "first_seen_at" => Time.current.iso8601 })
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])

      build_reaper(workspace_service: service).reap

      assert_nil marker_for("gone")
      assert marker_for("aixle-prod-1")
    end

    test "an expired marker restarts the confirmation instead of confirming a delete" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      create(
        :integration_data, :expired,
        integration: @integration, key: marker_key("aixle-prod-1"),
        value: { "kind" => "workspace_dead", "first_seen_at" => 2.days.ago.iso8601 }
      )

      result = build_reaper(workspace_service: service).reap

      assert_empty service.deleted_ids
      assert_equal 1, result[:marked]

      refreshed = marker_for("aixle-prod-1")
      assert_operator refreshed.expires_at, :>, Time.current
      assert_equal 1, @integration.integration_data.where(key: marker_key("aixle-prod-1")).count
    end

    test "only workspaces matching the integration's prefix are considered" do
      service = FakeWorkspaceService.new(workspaces: [
        running("aixle-prod-1", "u1"),
        running("someone-elses-box", "u9")
      ])

      result = build_reaper(workspace_service: service).reap

      assert_equal 1, result[:checked]
      assert_nil marker_for("someone-elses-box")
    end

    test "markers are scoped to their integration" do
      other   = create(:integration, :coder, :active, company: @company, connected_by: @user)
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])

      build_reaper(workspace_service: service).reap

      assert_nil other.integration_data.find_by(key: marker_key("aixle-prod-1"))
    end

    test "the reaper does nothing at all when it is switched off" do
      service = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])

      original = Settings.coder.reap_enabled
      Settings.coder.reap_enabled = false
      begin
        result = build_reaper(workspace_service: service).reap

        assert_equal false, result[:enabled] # rubocop:disable Minitest/RefuteFalse
        assert_equal 0, result[:checked]
        assert_nil marker_for("aixle-prod-1")
      ensure
        Settings.coder.reap_enabled = original
      end
    end

    # ---------- the cross-integration sweep ----------

    test "reap_all visits every active Coder integration and survives a failing one" do
      broken = create(:integration, :coder, :active, company: @company, connected_by: @user)
      create(:integration, :coder, company: @company, connected_by: @user, status: :error)
      create(:integration, :github, :active, company: @company, connected_by: @user)

      Coder::WorkspaceService.stubs(:new).with(@integration).returns(
        FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      )
      Coder::WorkspaceService.stubs(:new).with(broken).raises(
        Coder::WorkspaceService::OperationError.new("list workspaces failed: HTTP 401")
      )
      Coder::HealthCheck.stubs(:new).returns(FakeHealthCheck.new)

      totals = Coder::DeadWorkspaceReaper.reap_all

      assert_equal 1, totals[:integrations]
      assert_equal 1, totals[:marked]
      assert_equal 1, totals[:errors]
    end
  end
end
