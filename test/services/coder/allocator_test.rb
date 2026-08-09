# frozen_string_literal: true

require "test_helper"

module Coder
  class AllocatorTest < ActiveSupport::TestCase
    class FakeWorkspaceService
      attr_accessor :workspaces, :started_ids, :awaited_ids, :created

      def initialize(workspaces: [], created: nil, failing_start_ids: [])
        @workspaces        = workspaces
        @started_ids       = []
        @awaited_ids       = []
        @created           = created
        @failing_start_ids = failing_start_ids
      end

      def list(prefix: nil)
        return @workspaces if prefix.blank?
        @workspaces.select { |w| w["name"].to_s.start_with?(prefix) }
      end

      def start(workspace_id)
        @started_ids << workspace_id
        if @failing_start_ids.include?(workspace_id)
          raise Coder::WorkspaceService::OperationError,
                "build (start) failed: HTTP 500 spot capacity unavailable"
        end

        { "id" => "build-#{workspace_id}", "job" => { "status" => "succeeded" } }
      end

      def await_build(id, **)
        @awaited_ids << id
        { "job" => { "status" => "succeeded" } }
      end

      def create_workspace(name:, template_name: nil, template_id: nil)
        @created || {
          "id"           => "new-#{name}",
          "name"         => name,
          "latest_build" => { "id" => "build-new", "job" => { "status" => "succeeded" } }
        }
      end
    end

    # Stands in for Coder::HealthCheck's active tier (its own decision logic is
    # covered in health_check_test). Verdicts are keyed by workspace name;
    # anything unlisted comes back with the default.
    class FakeHealthCheck
      attr_reader :probed

      def initialize(verdicts = {}, default: :healthy)
        @verdicts = verdicts
        @default  = default
        @probed   = []
      end

      def probe(workspace_name:)
        @probed << workspace_name
        state = @verdicts.fetch(workspace_name, @default)
        Coder::HealthCheck::Result.new(
          state:  state,
          reason: "fake #{state}",
          load:   @verdicts.dig(:loads, workspace_name)
        )
      end
    end

    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @integration.update!(settings: @integration.settings.merge("machine_prefix" => "aixle-prod"))
      @session     = OpenStruct.new(id: "sess-1")
    end

    def build_allocator(workspace_service:, lock_service: Coder::LockService.new(@integration),
                        health_check: FakeHealthCheck.new, quarantine_service: nil)
      Coder::Allocator.new(
        integration:        @integration,
        terminal_session:   @session,
        workspace_service:  workspace_service,
        lock_service:       lock_service,
        health_check:       health_check,
        quarantine_service: quarantine_service || Coder::QuarantineService.new(@integration)
      )
    end

    def running(name, id)
      { "id" => id, "name" => name,
        "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
    end

    test "picks a running workspace first and locks it" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_equal "aixle-prod-1", result[:workspace_name]
      assert_equal "running", result[:status]
      assert_equal "coder ssh aixle-prod-1", result[:ssh_command]
      assert_empty ws.started_ids, "expected not to call start when workspace is already running"
    end

    test "starts a stopped workspace when there is no running one" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "stop", "job" => { "status" => "succeeded" } } }
      ])

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_equal "running", result[:status]
      assert_equal [ "u1" ], ws.started_ids
    end

    test "awaits an in-flight start-build instead of issuing a fresh start (avoids HTTP 409)" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => {
            "id" => "build-pending-1", "transition" => "start", "job" => { "status" => "pending" }
          } }
      ])

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_equal "aixle-prod-1", result[:workspace_name]
      assert_equal "running", result[:status]
      assert_empty ws.started_ids, "expected not to call start while a build is in flight"
      assert_includes ws.awaited_ids, "build-pending-1"
    end

    test "awaits an in-flight running start-build instead of issuing a fresh start" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => {
            "id" => "build-running-1", "transition" => "start", "job" => { "status" => "running" }
          } }
      ])

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_equal "running", result[:status]
      assert_empty ws.started_ids
      assert_includes ws.awaited_ids, "build-running-1"
    end

    test "skips a candidate that is locked by another session and tries the next" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } },
        { "id" => "u2", "name" => "aixle-prod-2",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])

      Coder::LockService.new(@integration).acquire(
        workspace_name: "aixle-prod-1", workspace_id: "u1", terminal_session_id: "sess-OTHER"
      )

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_equal "aixle-prod-2", result[:workspace_name]
    end

    test "falls through to creating a new workspace when all candidates are held" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])

      @integration.update!(settings: @integration.settings.merge("default_template" => "tpl-x"))
      Coder::LockService.new(@integration).acquire(
        workspace_name: "aixle-prod-1", workspace_id: "u1", terminal_session_id: "sess-OTHER"
      )

      allocator = build_allocator(workspace_service: ws)
      result = allocator.allocate

      assert_match(/\Aaixle-prod-[0-9a-f]+\z/, result[:workspace_name])
      assert_equal "starting", result[:status]
    end

    test "hands the lock back when a workspace fails to start and tries the next candidate" do
      ws = FakeWorkspaceService.new(
        workspaces: [
          { "id" => "u1", "name" => "aixle-prod-1",
            "latest_build" => { "transition" => "stop", "job" => { "status" => "succeeded" } } },
          { "id" => "u2", "name" => "aixle-prod-2",
            "latest_build" => { "transition" => "stop", "job" => { "status" => "succeeded" } } }
        ],
        failing_start_ids: [ "u1" ]
      )

      result = build_allocator(workspace_service: ws).allocate

      assert_equal "aixle-prod-2", result[:workspace_name]
      assert_nil @integration.integration_data.find_by(key: "coder:workspace_lock:aixle-prod-1"),
                 "a workspace that failed to start must not stay locked for the whole TTL"
      assert @integration.integration_data.find_by(key: "coder:workspace_lock:aixle-prod-2")
    end

    test "raises ExhaustedError when pool is empty and no default template configured" do
      ws = FakeWorkspaceService.new(workspaces: [])
      @integration.update!(settings: (@integration.settings || {}).merge("default_template" => nil))

      error = assert_raises(Coder::Allocator::ExhaustedError) do
        build_allocator(workspace_service: ws).allocate
      end
      assert_match(/no workspaces match prefix "aixle-prod"/, error.message)
      assert_match(/no default_template configured/, error.message)
    end

    test "ExhaustedError names the sessions-held workspaces instead of claiming the pool is empty" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } },
        { "id" => "u2", "name" => "aixle-prod-2",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])
      lock_service = Coder::LockService.new(@integration)
      lock_service.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", terminal_session_id: "sess-OTHER")
      lock_service.acquire(workspace_name: "aixle-prod-2", workspace_id: "u2", terminal_session_id: "sess-OTHER")

      error = assert_raises(Coder::Allocator::ExhaustedError) do
        build_allocator(workspace_service: ws).allocate
      end
      assert_match(/none of the 2 workspaces in the pool could be allocated/, error.message)
      assert_match(/2 held by other sessions \(aixle-prod-1, aixle-prod-2\)/, error.message)
    end

    test "ExhaustedError carries the reason a workspace failed to start" do
      ws = FakeWorkspaceService.new(
        workspaces: [
          { "id" => "u1", "name" => "aixle-prod-1",
            "latest_build" => { "transition" => "stop", "job" => { "status" => "succeeded" } } }
        ],
        failing_start_ids: [ "u1" ]
      )

      error = assert_raises(Coder::Allocator::ExhaustedError) do
        build_allocator(workspace_service: ws).allocate
      end
      assert_match(/1 failed to start: aixle-prod-1 \(build \(start\) failed: HTTP 500 spot capacity unavailable\)/,
                   error.message)
    end

    # ---------- health gating ----------

    test "probes the workspace it locked and hands it over when healthy" do
      ws     = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_equal "aixle-prod-1", result[:workspace_name]
      assert_equal [ "aixle-prod-1" ], health.probed
      assert_nil result[:health_warning]
    end

    test "quarantines a workspace that fails the probe, releases it, and allocates the next one" do
      ws     = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1"), running("aixle-prod-2", "u2") ])
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_equal "aixle-prod-2", result[:workspace_name]
      assert Coder::QuarantineService.new(@integration).quarantined?(workspace_name: "aixle-prod-1")
      assert_nil @integration.integration_data.find_by(key: "coder:workspace_lock:aixle-prod-1"),
                 "a workspace that failed its probe must not stay locked"
    end

    test "skips a quarantined workspace without probing it" do
      ws = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1"), running("aixle-prod-2", "u2") ])
      Coder::QuarantineService.new(@integration).quarantine(workspace_name: "aixle-prod-1", reason: "load 84")
      health = FakeHealthCheck.new

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_equal "aixle-prod-2", result[:workspace_name]
      assert_equal [ "aixle-prod-2" ], health.probed
    end

    test "skips a workspace whose coder agent reports it unhealthy" do
      unhealthy = running("aixle-prod-1", "u1").merge(
        "latest_build" => running("aixle-prod-1", "u1")["latest_build"].merge(
          "resources" => [ { "agents" => [ { "status" => "disconnected" } ] } ]
        )
      )
      ws = FakeWorkspaceService.new(workspaces: [ unhealthy, running("aixle-prod-2", "u2") ])

      result = build_allocator(workspace_service: ws).allocate

      assert_equal "aixle-prod-2", result[:workspace_name]
    end

    test "excludes the workspaces the caller refuses" do
      ws = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1"), running("aixle-prod-2", "u2") ])

      result = build_allocator(workspace_service: ws).allocate(exclude: [ "aixle-prod-1" ])

      assert_equal "aixle-prod-2", result[:workspace_name]
    end

    # D-0: allocation must never be worse than it was before health gating. A
    # pool where everything looks sick still yields a workspace — with a
    # warning, not an exception.
    test "falls back to the least-bad workspace when every candidate fails its probe" do
      ws     = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1"), running("aixle-prod-2", "u2") ])
      health = FakeHealthCheck.new(
        { "aixle-prod-1" => :sick, "aixle-prod-2" => :sick,
          loads: { "aixle-prod-1" => 90.0, "aixle-prod-2" => 12.0 } }
      )

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_equal "aixle-prod-2", result[:workspace_name], "expected the lower-load box"
      assert_match(/no healthy workspace was available/, result[:health_warning])
      assert Coder::LockService.new(@integration).held_by_session?(
        workspace_name: "aixle-prod-2", terminal_session_id: @session.id
      )
    end

    test "allocates normally when the probe cannot run at all" do
      ws     = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new({}, default: :unknown)

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_equal "aixle-prod-1", result[:workspace_name]
      assert_nil result[:health_warning]
      assert_not Coder::QuarantineService.new(@integration).quarantined?(workspace_name: "aixle-prod-1")
    end

    test "prefers creating a workspace over reusing an unhealthy one" do
      ws     = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })
      @integration.update!(settings: @integration.settings.merge("default_template" => "tpl-x"))

      result = build_allocator(workspace_service: ws, health_check: health).allocate

      assert_match(/\Aaixle-prod-[0-9a-f]+\z/, result[:workspace_name])
      assert_equal "starting", result[:status]
    end

    test "a successful probe clears a stale quarantine row" do
      ws = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      quarantine = Coder::QuarantineService.new(@integration)
      quarantine.quarantine(workspace_name: "aixle-prod-1", reason: "old", minutes: -1)

      build_allocator(workspace_service: ws).allocate

      assert_nil @integration.integration_data.find_by(key: "coder:workspace_health:aixle-prod-1"),
                 "a workspace that passes its probe must not keep an old quarantine row"
    end

    test "ExhaustedError explains the unhealthy candidates it could not fall back to" do
      ws = FakeWorkspaceService.new(workspaces: [ running("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })
      lock_service = Coder::LockService.new(@integration)

      allocator = build_allocator(workspace_service: ws, health_check: health, lock_service: lock_service)

      # The probe releases the lock; another session grabs it before the
      # fallback can, so there is genuinely nothing left to hand over.
      lock_service.define_singleton_method(:acquire) do |**kwargs|
        raise Coder::LockService::LockNotAcquired, "taken" if @seen_once

        @seen_once = true
        super(**kwargs)
      end

      error = assert_raises(Coder::Allocator::ExhaustedError) { allocator.allocate }
      assert_match(/unhealthy and unlockable: aixle-prod-1/, error.message)
    end

    test "lock value records terminal_session_id and never task_id / step_run_id" do
      ws = FakeWorkspaceService.new(workspaces: [
        { "id" => "u1", "name" => "aixle-prod-1",
          "latest_build" => { "transition" => "start", "job" => { "status" => "succeeded" } } }
      ])

      build_allocator(workspace_service: ws).allocate

      lock = @integration.integration_data.find_by(key: "coder:workspace_lock:aixle-prod-1")
      assert_equal "sess-1", lock.value["terminal_session_id"]
      assert_nil lock.value["task_id"]
      assert_nil lock.value["task_link"]
      assert_nil lock.value["step_run_id"]
    end
  end
end
