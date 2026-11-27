# frozen_string_literal: true

require "test_helper"

module Coder
  # `allocate(wait: false)` and `delete` against the real WorkspaceService and
  # WebMock, so what is asserted is the Coder traffic: no build is waited on,
  # and a workspace is handed over only when it is ready.
  class AllocatorNowaitTest < ActiveSupport::TestCase
    # Stands in for Coder::HealthCheck's active tier (its decision logic is in
    # health_check_test).
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
        Coder::HealthCheck::Result.new(state: state, reason: "fake #{state}", reachable: state == :healthy)
      end
    end

    JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

    setup do
      resolve_hosts_publicly!
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @integration.update!(settings: @integration.settings.merge("machine_prefix" => "aixle-prod"))
      @base        = @integration.coder_url
      @holder      = Coder::LockService::Holder.environment(7)
      @locks       = Coder::LockService.new(@integration)
    end

    def with_template!
      @integration.update!(settings: @integration.settings.merge("default_template" => "pool"))
      stub_json(:get, "/api/v2/templates", [ { id: "t1", name: "pool" } ])
    end

    def stub_json(method, path, body, status: 200)
      stub_request(method, "#{@base}#{path}")
        .to_return(status: status, body: body.to_json, headers: JSON_HEADERS)
    end

    def stub_list(workspaces)
      stub_request(:get, "#{@base}/api/v2/workspaces").with(query: { q: "owner:me" })
        .to_return(status: 200, body: { workspaces: workspaces }.to_json, headers: JSON_HEADERS)
    end

    def workspace(name, id, transition: "start", job: "succeeded", agent: "connected", build_id: "b-#{id}")
      resources = agent ? [ { agents: [ { status: agent } ] } ] : []
      { id: id, name: name,
        latest_build: { id: build_id, transition: transition, job: { status: job }, resources: resources } }
    end

    def stub_workspace(name, **opts)
      stub_json(:get, "/api/v2/users/me/workspace/#{name}", workspace(name, opts.delete(:id) || "u1", **opts))
    end

    def allocator(health: FakeHealthCheck.new, holder: @holder)
      Coder::Allocator.new(integration: @integration, holder: holder, health_check: health)
    end

    def hold_row(name = "aixle-prod-1")
      @integration.integration_data.find_by(key: "coder:workspace_lock:#{name}")
    end

    # ---------- a new workspace ----------

    test "a new workspace is created and returned pending without waiting for its build" do
      with_template!
      stub_list([])
      create = stub_json(:post, "/api/v2/users/#{@integration.coder_user_id}/workspaces",
                         { id: "n1", name: "aixle-prod-new", latest_build: { id: "b-new", job: { status: "pending" } } }, status: 201)

      result = allocator.allocate(wait: false)

      assert result.pending?
      assert_equal "Building workspace aixle-prod-new", result.message
      assert_equal "n1", result.workspace[:workspace_id]
      assert_requested create, times: 1
      assert_not_requested :get, %r{/api/v2/workspacebuilds/}
      assert_equal "7", @integration.integration_data.find_by("value ->> 'workspace_id' = 'n1'").value["runner_environment_id"]
    end

    # ---------- a workspace of the pool ----------

    test "a stopped workspace is started and returned pending without waiting for its build" do
      stub_list([ workspace("aixle-prod-1", "u1", transition: "stop") ])
      start = stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds").with(body: { transition: "start" }.to_json)
                .to_return(status: 201, body: { id: "b-start", job: { status: "pending" } }.to_json, headers: JSON_HEADERS)

      result = allocator.allocate(wait: false)

      assert result.pending?
      assert_equal "Starting workspace aixle-prod-1", result.message
      assert_equal "aixle-prod-1", result.workspace[:workspace_name]
      assert_requested start, times: 1
      assert_not_requested :get, %r{/api/v2/workspacebuilds/}
      assert_nil hold_row.expires_at, "the hold is explicit"
    end

    test "a running workspace whose agent is connected and whose probe passed is ready" do
      stub_list([ workspace("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new

      result = allocator(health: health).allocate(wait: false)

      assert result.ready?
      assert_equal "aixle-prod-1", result.workspace[:workspace_name]
      assert_equal "running", result.workspace[:status]
      assert_nil result.workspace[:lock_expires_at]
      assert_equal [ "aixle-prod-1" ], health.probed
    end

    test "a workspace whose build is still in flight is pending and is not probed" do
      stub_list([ workspace("aixle-prod-1", "u1", job: "running") ])
      health = FakeHealthCheck.new

      result = allocator(health: health).allocate(wait: false)

      assert result.pending?
      assert_equal "Starting workspace aixle-prod-1", result.message
      assert_empty health.probed
      assert_not_requested :post, %r{/builds}
    end

    test "a built workspace whose agent has not connected is pending and is not probed" do
      stub_list([ workspace("aixle-prod-1", "u1", agent: "connecting") ])
      health = FakeHealthCheck.new

      result = allocator(health: health).allocate(wait: false)

      assert result.pending?
      assert_equal "Waiting for the agent of aixle-prod-1", result.message
      assert_empty health.probed
    end

    test "it takes a free workspace and passes over one held by someone else" do
      stub_list([ workspace("aixle-prod-1", "u1"), workspace("aixle-prod-2", "u2") ])
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: Coder::LockService::Holder.session("sess-A"))
      @locks.acquire(workspace_name: "aixle-prod-3", workspace_id: "u3", holder: Coder::LockService::Holder.environment(99))

      result = allocator.allocate(wait: false)

      assert result.ready?
      assert_equal "aixle-prod-2", result.workspace[:workspace_name]
    end

    test "it raises ExhaustedError when it has nothing to give" do
      stub_list([])

      error = assert_raises(Coder::Allocator::ExhaustedError) { allocator.allocate(wait: false) }

      assert_match(/no default_template configured/, error.message)
    end

    test "a refusal for quota on create is an ExhaustedError carrying Coder's message" do
      with_template!
      stub_list([])
      stub_json(:post, "/api/v2/users/#{@integration.coder_user_id}/workspaces",
                { message: "Quota exceeded", detail: "the workspace quota is used up" }, status: 403)

      error = assert_raises(Coder::Allocator::ExhaustedError) { allocator.allocate(wait: false) }

      assert_match(/Quota exceeded/, error.message)
    end

    test "a create refusal that is not about quota is raised, not turned into ExhaustedError" do
      with_template!
      stub_list([])
      stub_json(:post, "/api/v2/users/#{@integration.coder_user_id}/workspaces",
                { message: "Missing required parameter", detail: "region" }, status: 400)

      error = assert_raises(Coder::WorkspaceService::OperationError) { allocator.allocate(wait: false) }

      assert_not_kind_of Coder::Allocator::ExhaustedError, error
      assert_not_kind_of Coder::WorkspaceService::QuotaError, error
      assert_match(/Missing required parameter/, error.message)
    end

    # ---------- a probe that fails ----------

    test "a workspace that fails its probe is never handed over and is not held any more" do
      stub_list([ workspace("aixle-prod-1", "u1") ])
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })

      assert_raises(Coder::Allocator::ExhaustedError) { allocator(health: health).allocate(wait: false) }

      assert_nil hold_row, "the lock is released"
      assert Coder::QuarantineService.new(@integration).quarantined?(workspace_name: "aixle-prod-1")
    end

    test "a workspace that fails its probe is passed over for a new one" do
      with_template!
      stub_list([ workspace("aixle-prod-1", "u1") ])
      stub_json(:post, "/api/v2/users/#{@integration.coder_user_id}/workspaces",
                { id: "n1", name: "aixle-prod-new", latest_build: { id: "b-new", job: { status: "pending" } } }, status: 201)
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })

      result = allocator(health: health).allocate(wait: false)

      assert result.pending?
      assert_not_equal "aixle-prod-1", result.workspace[:workspace_name]
      assert_nil hold_row
    end

    # ---------- a retry ----------

    test "a retry for the same holder continues the same workspace, from where it stands" do
      list = stub_list([ workspace("aixle-prod-1", "u1", transition: "stop") ])
      stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds")
        .to_return(status: 201, body: { id: "b-start", job: { status: "pending" } }.to_json, headers: JSON_HEADERS)
      health = FakeHealthCheck.new

      first = allocator(health: health).allocate(wait: false)
      assert first.pending?

      stub_workspace("aixle-prod-1", job: "running", build_id: "b-start")
      second = allocator(health: health).allocate(wait: false)
      assert second.pending?
      assert_equal "aixle-prod-1", second.workspace[:workspace_name]

      stub_workspace("aixle-prod-1", agent: "connecting", build_id: "b-start")
      third = allocator(health: health).allocate(wait: false)
      assert third.pending?
      assert_equal "Waiting for the agent of aixle-prod-1", third.message

      stub_workspace("aixle-prod-1", build_id: "b-start")
      fourth = allocator(health: health).allocate(wait: false)
      assert fourth.ready?
      assert_equal "aixle-prod-1", fourth.workspace[:workspace_name]

      assert_requested list, times: 1
      assert_requested :post, "#{@base}/api/v2/workspaces/u1/builds", times: 1
      assert_equal 1, @integration.integration_data.with_key_prefix(Coder::LockService::LOCK_KEY_PREFIX).count
    end

    test "allocate is idempotent for a holder that holds a workspace" do
      stub_list([ workspace("aixle-prod-1", "u1"), workspace("aixle-prod-2", "u2") ])
      stub_workspace("aixle-prod-1")

      first  = allocator.allocate(wait: false)
      second = allocator.allocate(wait: false)

      assert_equal first.workspace[:workspace_name], second.workspace[:workspace_name]
      assert second.ready?
    end

    test "a retry whose workspace failed its probe since is passed over, not handed over" do
      stub_list([ workspace("aixle-prod-1", "u1"), workspace("aixle-prod-2", "u2") ])
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_workspace("aixle-prod-1")
      health = FakeHealthCheck.new({ "aixle-prod-1" => :sick })

      result = allocator(health: health).allocate(wait: false)

      assert result.ready?
      assert_equal "aixle-prod-2", result.workspace[:workspace_name]
      assert_nil hold_row("aixle-prod-1")
    end

    test "a retry whose workspace build failed raises OperationError with the build's message" do
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_json(:get, "/api/v2/users/me/workspace/aixle-prod-1", {
        id: "u1", name: "aixle-prod-1",
        latest_build: { id: "b1", transition: "start", job: { status: "failed", error: "no capacity" } }
      })

      error = assert_raises(Coder::WorkspaceService::OperationError) { allocator.allocate(wait: false) }

      assert_match(/no capacity/, error.message)
      assert hold_row, "the hold stays until the workspace is deleted"
    end

    test "a retry whose workspace build failed does not show the integration token in the message" do
      token = @integration.credentials_data["session_token"]
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_json(:get, "/api/v2/users/me/workspace/aixle-prod-1", {
        id: "u1", name: "aixle-prod-1",
        latest_build: { id: "b1", transition: "start", job: { status: "failed", error: "auth #{token} rejected" } }
      })

      error = assert_raises(Coder::WorkspaceService::OperationError) { allocator.allocate(wait: false) }

      assert_match(/rejected/, error.message)
      assert_not_includes error.message, token
    end

    # ---------- delete ----------

    test "delete starts a delete build and is pending until Coder reports the workspace deleted" do
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_workspace("aixle-prod-1")
      del = stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds").with(body: { transition: "delete" }.to_json)
              .to_return(status: 201, body: { id: "b-del", job: { status: "pending" } }.to_json, headers: JSON_HEADERS)

      assert_equal :pending, allocator.delete(holder: @holder)
      assert_requested del, times: 1
      assert hold_row, "the hold stays while the delete runs"

      stub_workspace("aixle-prod-1", transition: "delete", job: "running")
      assert_equal :pending, allocator.delete(holder: @holder)
      assert_requested del, times: 1
      assert hold_row

      stub_workspace("aixle-prod-1", transition: "delete", job: "succeeded")
      assert_equal :gone, allocator.delete(holder: @holder)
      assert_nil hold_row, "the hold is released when the workspace is deleted"
    end

    test "delete is gone for a holder that holds no workspace" do
      assert_equal :gone, allocator.delete(holder: @holder)
      assert_not_requested :any, %r{/api/v2/}
    end

    test "delete is gone for a workspace Coder no longer knows, and releases the hold" do
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_json(:get, "/api/v2/users/me/workspace/aixle-prod-1", { message: "Not found" }, status: 404)

      assert_equal :gone, allocator.delete(holder: @holder)
      assert_nil hold_row
    end

    test "delete raises OperationError when Coder refuses it, and keeps the hold" do
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: @holder)
      stub_workspace("aixle-prod-1")
      stub_request(:post, "#{@base}/api/v2/workspaces/u1/builds").to_return(status: 409)

      error = assert_raises(Coder::WorkspaceService::OperationError) { allocator.delete(holder: @holder) }

      assert_match(/build \(delete\) failed/, error.message)
      assert hold_row
    end

    test "delete finds a workspace locked before any name was recorded by its holder" do
      # The crash window of the caller: the lock is taken, nothing else is written.
      @locks.acquire(workspace_name: "aixle-prod-9", workspace_id: "u9", holder: @holder)
      stub_workspace("aixle-prod-9", id: "u9", agent: nil)
      del = stub_request(:post, "#{@base}/api/v2/workspaces/u9/builds").with(body: { transition: "delete" }.to_json)
              .to_return(status: 201, body: { id: "b-del", job: { status: "pending" } }.to_json, headers: JSON_HEADERS)

      assert_equal :pending, allocator.delete(holder: @holder)
      assert_requested del, times: 1
    end

    test "delete leaves the workspaces of other holders alone" do
      @locks.acquire(workspace_name: "aixle-prod-1", workspace_id: "u1", holder: Coder::LockService::Holder.environment(8))

      assert_equal :gone, allocator.delete(holder: @holder)
      assert hold_row
    end
  end
end
