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
      { workspace_name: workspace_name, workspace_id: workspace_id, holder: Coder::LockService::Holder.session(terminal_session_id) }
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

    # One pool, reached through two integrations — two companies, or two projects of
    # one — is still one set of machines.
    test "a box locked through one integration cannot be locked through another" do
      other_company = create(:company)
      other = create(:integration, :coder, :active, company: other_company,
                                                    connected_by: create(:user, :admin, company: other_company))
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      error = assert_raises(Coder::LockService::LockNotAcquired) do
        Coder::LockService.new(other).acquire(**lock_args(workspace_name: "ws-1", terminal_session_id: "sess-B"))
      end
      assert_match(/another integration/, error.message)
    end

    test "another integration's expired lock on the box does not keep it" do
      other_company = create(:company)
      other = create(:integration, :coder, :active, company: other_company,
                                                    connected_by: create(:user, :admin, company: other_company))
      Coder::LockService.new(other).acquire(**lock_args(terminal_session_id: "sess-A"))
      IntegrationData.where(integration: other).update_all(expires_at: 1.minute.ago)

      assert @service.acquire(**lock_args(terminal_session_id: "sess-B"))
      assert_not IntegrationData.exists?(integration: other)
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

      @service.release_for_session(holder: Coder::LockService::Holder.session("sess-A"))

      assert_not @service.held?(workspace_name: "ws-1")
      assert_not @service.held?(workspace_name: "ws-2")
      assert     @service.held?(workspace_name: "ws-3")
    end

    test "release_owned deletes the row only for the holding session" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert_not @service.release_owned(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-B"))
      assert @service.held?(workspace_name: "ws-1"), "another session must not be able to release the lock"

      assert @service.release_owned(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-A"))
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

      assert_not @service.release_owned(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-A"))
      assert @service.held_by_session?(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-B"))
    end

    test "release_owned is idempotent on missing rows" do
      assert_not @service.release_owned(workspace_name: "missing", holder: Coder::LockService::Holder.session("sess-A"))
    end

    test "held_by_session? returns true only for the holder" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert     @service.held_by_session?(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-A"))
      assert_not @service.held_by_session?(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-B"))
    end

    # Same name, different machines: another Coder user's (or deployment's) "ws-1".
    test "two integrations isolate their locks for different machines of the same name" do
      other = create(:integration, :coder, :active, company: @company, connected_by: @user)
      other_service = Coder::LockService.new(other)

      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      assert_nothing_raised do
        other_service.acquire(**lock_args(workspace_id: "ws-uuid-2", terminal_session_id: "sess-A"))
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
        assert @service.touch(workspace_name: "ws-1", holder: lock_args[:holder])
      end

      assert_operator @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at,
                      :>, original
    end

    test "touch does not renew a lock held by another session" do
      row = @service.acquire(**lock_args(terminal_session_id: "sess-OWNER"))

      assert_not @service.touch(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("sess-OTHER"))
      assert_equal row.expires_at.to_i,
                   @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at.to_i
    end

    test "touch on a workspace nobody holds reports false" do
      assert_not @service.touch(workspace_name: "ws-missing", holder: Coder::LockService::Holder.session("sess-1"))
    end

    # ---------- an environment holder: an explicit hold ----------

    def environment(id = 7) = Coder::LockService::Holder.environment(id)

    def env_lock_args(workspace_name: "ws-1", workspace_id: "ws-uuid-1", environment_id: 7)
      { workspace_name: workspace_name, workspace_id: workspace_id, holder: environment(environment_id) }
    end

    test "Holder derives the lock value's key and the explicit hold from its kind" do
      session = Coder::LockService::Holder.session(5)

      assert_equal "terminal_session_id", session.value_key
      assert_not session.explicit?
      assert_equal "5", session.id
      assert_equal "runner_environment_id", environment.value_key
      assert environment.explicit?
      assert_raises(ArgumentError) { Coder::LockService::Holder.new(kind: :other, id: 1) }
      assert_raises(ArgumentError) { Coder::LockService::Holder.session("") }
    end

    test "an environment holder's lock has no expiry and records the environment id" do
      row = @service.acquire(**env_lock_args)

      assert_nil row.expires_at
      assert_equal "7", row.value["runner_environment_id"]
      assert_nil row.value["terminal_session_id"]
      assert @service.held?(workspace_name: "ws-1")
    end

    test "an environment's lock is never reclaimed by expiry" do
      @service.acquire(**env_lock_args)

      travel 30.days do
        assert_raises(Coder::LockService::LockNotAcquired) do
          @service.acquire(**lock_args(terminal_session_id: "sess-B"))
        end
        assert @service.held?(workspace_name: "ws-1")
        assert_equal 1, @service.live_locks.count
      end
    end

    test "an environment holder does not take a workspace a session holds, nor the reverse" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))
      assert_raises(Coder::LockService::LockNotAcquired) { @service.acquire(**env_lock_args) }

      @service.acquire(**env_lock_args(workspace_name: "ws-2", workspace_id: "u2"))
      assert_raises(Coder::LockService::LockNotAcquired) do
        @service.acquire(**lock_args(workspace_name: "ws-2", workspace_id: "u2", terminal_session_id: "7"))
      end
    end

    test "an environment id equal to a session id does not make them the same holder" do
      @service.acquire(**lock_args(terminal_session_id: "7"))

      assert_not @service.held_by_session?(workspace_name: "ws-1", holder: environment(7))
      assert_nil @service.held_by(holder: environment(7))
    end

    test "release_all_for_session leaves an environment's lock alone" do
      project = create(:project, company: @company, owner: @user)
      @service.acquire(**env_lock_args(workspace_name: "ws-env", workspace_id: "u-env", environment_id: 7))
      @service.acquire(**lock_args(workspace_name: "ws-1", workspace_id: "u1", terminal_session_id: "7"))

      Coder::LockService.release_all_for_session(OpenStruct.new(id: 7, project: project))

      assert @service.held?(workspace_name: "ws-env")
      assert_not @service.held?(workspace_name: "ws-1")
    end

    test "release_owned releases an environment's lock, and only for that environment" do
      @service.acquire(**env_lock_args)

      assert_not @service.release_owned(workspace_name: "ws-1", holder: environment(8))
      assert_not @service.release_owned(workspace_name: "ws-1", holder: Coder::LockService::Holder.session("7"))
      assert @service.release_owned(workspace_name: "ws-1", holder: environment(7))
      assert_not @service.held?(workspace_name: "ws-1")
    end

    test "touch leaves an environment's hold without an expiry" do
      @service.acquire(**env_lock_args)

      assert @service.touch(workspace_name: "ws-1", holder: environment(7))
      assert_nil @integration.integration_data.find_by(key: "coder:workspace_lock:ws-1").expires_at
      assert_not @service.touch(workspace_name: "ws-1", holder: environment(8))
    end

    test "held_by returns the workspace a holder holds, and nil for a holder with none" do
      @service.acquire(**env_lock_args(workspace_name: "ws-9", workspace_id: "u9"))

      hold = @service.held_by(holder: environment(7))

      assert_equal "ws-9", hold.workspace_name
      assert_equal "u9", hold.workspace_id
      assert_nil hold.expires_at
      assert_nil @service.held_by(holder: environment(8))
    end

    test "held_by does not return an expired session lock" do
      @service.acquire(**lock_args(terminal_session_id: "sess-A"))

      travel 3.hours do
        assert_nil @service.held_by(holder: Coder::LockService::Holder.session("sess-A"))
      end
    end
  end
end
