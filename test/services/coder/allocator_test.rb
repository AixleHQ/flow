# frozen_string_literal: true

require "test_helper"

module Coder
  class AllocatorTest < ActiveSupport::TestCase
    class FakeWorkspaceService
      attr_accessor :workspaces, :started_ids, :awaited_ids, :created

      def initialize(workspaces: [], created: nil)
        @workspaces  = workspaces
        @started_ids = []
        @awaited_ids = []
        @created     = created
      end

      def list(prefix: nil)
        return @workspaces if prefix.blank?
        @workspaces.select { |w| w["name"].to_s.start_with?(prefix) }
      end

      def start(workspace_id)
        @started_ids << workspace_id
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

    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @integration.update!(settings: @integration.settings.merge("machine_prefix" => "aixle-prod"))
      @session     = OpenStruct.new(id: "sess-1")
    end

    def build_allocator(workspace_service:, lock_service: Coder::LockService.new(@integration))
      Coder::Allocator.new(
        integration:       @integration,
        terminal_session:  @session,
        workspace_service: workspace_service,
        lock_service:      lock_service
      )
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
      assert ws.started_ids.empty?, "expected not to call start when workspace is already running"
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
      assert ws.started_ids.empty?, "expected not to call start while a build is in flight"
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
      assert ws.started_ids.empty?
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

    test "raises ExhaustedError when pool is empty and no default template configured" do
      ws = FakeWorkspaceService.new(workspaces: [])
      @integration.update!(settings: (@integration.settings || {}).merge("default_template" => nil))

      assert_raises(Coder::Allocator::ExhaustedError) do
        build_allocator(workspace_service: ws).allocate
      end
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
