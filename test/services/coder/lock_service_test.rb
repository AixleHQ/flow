# frozen_string_literal: true

require "test_helper"

module Coder
  class LockServiceTest < ActiveSupport::TestCase
    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @service     = Coder::LockService.new(@integration)
    end

    def lock_args(workspace_name: "ws-1", workspace_id: "ws-uuid-1", terminal_session_id: "sess-1")
      { workspace_name: workspace_name, workspace_id: workspace_id, terminal_session_id: terminal_session_id }
    end

    test "acquire creates a row keyed by integration + workspace name" do
      row = @service.acquire(**lock_args)

      assert row
      assert_equal "coder:workspace_lock:ws-1", row.key
      assert_equal "sess-1", row.value["terminal_session_id"]
      assert_equal "ws-uuid-1", row.value["workspace_id"]
      assert_in_delta @integration.coder_lock_ttl_minutes.minutes.from_now.to_i, row.expires_at.to_i, 5
    end

    test "acquire raises when the workspace is held by another live session" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert_raises Coder::LockService::LockNotAcquired do
        @service.acquire(**lock_args(terminal_session_id: "sess-B"))
      end
    end

    test "acquire reclaims an expired row in a single statement" do
      stale = create(
        :integration_data, :expired,
        integration: @integration,
        key:         "coder:workspace_lock:ws-1",
        value:       { terminal_session_id: "old", workspace_id: "old-uuid" }
      )

      row = @service.acquire(**lock_args(terminal_session_id: "sess-new"))

      assert_equal stale.id, row.id, "should reuse the same row id via ON CONFLICT"
      assert_equal "sess-new", row.value["terminal_session_id"]
    end

    test "release deletes the lock row" do
      @service.acquire(**lock_args)
      assert @service.held?(workspace_name: "ws-1")

      @service.release(workspace_name: "ws-1")
      assert_not @service.held?(workspace_name: "ws-1")
    end

    test "release is idempotent on missing rows" do
      assert_nothing_raised do
        @service.release(workspace_name: "missing")
      end
    end

    test "release_for_session deletes only the session's locks" do
      @service.acquire(**lock_args(workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: "sess-A"))
      @service.acquire(**lock_args(workspace_name: "ws-2", workspace_id: "u2", terminal_session_id: "sess-A"))
      @service.acquire(**lock_args(workspace_name: "ws-3", workspace_id: "u3", terminal_session_id: "sess-B"))

      @service.release_for_session(terminal_session_id: "sess-A")

      assert_not @service.held?(workspace_name: "ws-1")
      assert_not @service.held?(workspace_name: "ws-2")
      assert     @service.held?(workspace_name: "ws-3")
    end

    test "release_owned deletes the row only for the holding session" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert_not @service.release_owned(workspace_name: "ws-1", terminal_session_id: "sess-B")
      assert @service.held?(workspace_name: "ws-1"), "another session must not be able to release the lock"

      assert @service.release_owned(workspace_name: "ws-1", terminal_session_id: "sess-A")
      assert_not @service.held?(workspace_name: "ws-1")
    end

    test "release_owned keeps a lock that another session reclaimed after expiry" do
      create(
        :integration_data, :expired,
        integration: @integration,
        key:         "coder:workspace_lock:ws-1",
        value:       { terminal_session_id: "sess-A", workspace_id: "u1" }
      )
      @service.acquire(**lock_args(terminal_session_id: "sess-B"))

      assert_not @service.release_owned(workspace_name: "ws-1", terminal_session_id: "sess-A")
      assert @service.held_by_session?(workspace_name: "ws-1", terminal_session_id: "sess-B")
    end

    test "release_owned is idempotent on missing rows" do
      assert_not @service.release_owned(workspace_name: "missing", terminal_session_id: "sess-A")
    end

    test "held_by_session? returns true only for the holder" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert     @service.held_by_session?(workspace_name: "ws-1", terminal_session_id: "sess-A")
      assert_not @service.held_by_session?(workspace_name: "ws-1", terminal_session_id: "sess-B")
    end

    test "two integrations isolate their locks for the same workspace name" do
      other = create(:integration, :coder, :active, company: @company, connected_by: @user)
      other_service = Coder::LockService.new(other)

      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      # No conflict — different integration_id, even with the same key.
      assert_nothing_raised do
        other_service.acquire(**lock_args(terminal_session_id: "sess-A"))
      end

      # release on one does not affect the other.
      @service.release(workspace_name: "ws-1")
      assert_not @service.held?(workspace_name: "ws-1")
      assert other_service.held?(workspace_name: "ws-1")
    end

    test "uses default 120-minute TTL when integration has no override" do
      @integration.settings = (@integration.settings || {}).merge("lock_ttl_minutes" => nil)
      @integration.save!

      row = @service.acquire(**lock_args)
      assert_in_delta 120.minutes.from_now.to_i, row.expires_at.to_i, 5
    end

    test "release_all_for_session iterates every active Coder integration in scope" do
      project = create(:project, company: @company, owner: @user)
      other   = create(:integration, :coder, :active, company: @company, connected_by: @user)

      session = OpenStruct.new(id: "sess-X", project: project)

      Coder::LockService.new(@integration).acquire(**lock_args(terminal_session_id: "sess-X"))
      Coder::LockService.new(other).acquire(**lock_args(workspace_name: "ws-2", workspace_id: "u2", terminal_session_id: "sess-X"))

      Coder::LockService.release_all_for_session(session)

      assert_not Coder::LockService.new(@integration).held?(workspace_name: "ws-1")
      assert_not Coder::LockService.new(other).held?(workspace_name: "ws-2")
    end

    test "release_all_for_session is a no-op when session has no project" do
      assert_nothing_raised do
        Coder::LockService.release_all_for_session(OpenStruct.new(id: "s", project: nil))
      end
    end

    # The TTL has to measure silence, not time since allocation: a step that
    # dies hard used to hold its workspace for the full window, which is how an
    # eight-machine pool presented as a one-machine pool.
    test "touch pushes the expiry forward for the holding session" do
      row = @service.acquire(**lock_args)
      original = row.expires_at

      travel 10.minutes do
        assert @service.touch(workspace_name: "ws-1", terminal_session_id: lock_args[:terminal_session_id])
      end

      assert_operator @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at,
                      :>, original
    end

    test "touch does not renew a lock held by another session" do
      row = @service.acquire(**lock_args(terminal_session_id: "sess-OWNER"))

      assert_not @service.touch(workspace_name: "ws-1", terminal_session_id: "sess-OTHER")
      assert_equal row.expires_at.to_i,
                   @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at.to_i
    end

    test "touch on a workspace nobody holds reports false" do
      assert_not @service.touch(workspace_name: "ws-missing", terminal_session_id: "sess-1")
    end
  end
end
