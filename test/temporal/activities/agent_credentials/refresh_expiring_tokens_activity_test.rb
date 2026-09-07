# frozen_string_literal: true

require "test_helper"

module Activities
  module AgentCredentials
    # Runs the real activity through the SDK's serverless ActivityEnvironment
    # (docs/testing.md §2). The DB scope (AgentCredential.refreshable.refresh_due)
    # and the adapter's refresh! are boundaries owned by other builders, so they
    # are stubbed here — this test pins the activity's own behavior: count
    # aggregation, per-record rescue, and the { refreshed:, not_needed:, errors: }
    # return shape.
    class RefreshExpiringTokensActivityTest < ActiveSupport::TestCase
      # A credential stand-in whose adapter.refresh! returns a fixed status Hash.
      def credential_double(id:, agent_type:, status:, detail: nil)
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: status, detail: detail })
        stub(id: id, agent_type: agent_type, adapter: adapter)
      end

      # Point AgentCredential.refreshable.refresh_due(REFRESH_WINDOW) at a fixed
      # collection that responds to find_each (the activity iterates with it).
      # `held` stands for credentials a live container holds: they are due, but the
      # sweep must leave them alone and only report how many it skipped.
      def stub_due(records, held: 0)
        records.define_singleton_method(:find_each) { |&blk| each(&blk) }
        due = mock("due_relation")
        due.stubs(:count).returns(records.size + held)
        due.stubs(:without_live_session).returns(records)
        refreshable = mock("refreshable_relation")
        refreshable.stubs(:refresh_due)
          .with(RefreshExpiringTokensActivity::REFRESH_WINDOW)
          .returns(due)
        ::AgentCredential.stubs(:refreshable).returns(refreshable)
      end

      test "aggregates counts across refreshed / not_needed / error statuses" do
        refreshed_cred = credential_double(id: 1, agent_type: "claude_code", status: :refreshed)
        refreshed_cred.stubs(:refresh_error).returns(nil)
        error_cred = credential_double(id: 3, agent_type: "codex", status: :error, detail: "boom")
        error_cred.stubs(:mark_refresh_error!)

        stub_due([
          refreshed_cred,
          credential_double(id: 2, agent_type: "claude_code", status: :not_needed),
          error_cred
        ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:not_needed]
        assert_equal 1, result[:errors]
      end

      test "per-record rescue keeps the batch going when one credential raises" do
        raising_adapter = mock("adapter")
        raising_adapter.stubs(:refresh!).raises(StandardError.new("kaboom"))
        bad = stub(id: 9, agent_type: "claude_code", adapter: raising_adapter)
        bad.stubs(:mark_refresh_error!)
        good = credential_double(id: 10, agent_type: "claude_code", status: :refreshed)
        good.stubs(:refresh_error).returns(nil)

        stub_due([ bad, good ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:errors]
        assert_equal 0, result[:not_needed]
      end

      test "returns zero counts when nothing is due" do
        stub_due([])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal({ refreshed: 0, not_needed: 0, errors: 0, held: 0 }, result)
      end

      # Refreshing a token a container also holds replays a grant that container may
      # already have rotated, so the sweep leaves it alone — and says how many it left.
      test "leaves credentials a live session holds to that session and counts them" do
        credential = credential_double(id: 1, agent_type: "claude_code", status: :refreshed)
        credential.stubs(:refresh_error).returns(nil)

        stub_due([ credential ], held: 2)

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 2, result[:held]
        assert_equal 1, result[:refreshed]
      end

      test "marks credential with permanent error on invalid_grant" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: :error, detail: "claudeAiOauth invalid_grant — reconnection required" })
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.expects(:mark_refresh_error!).with("claudeAiOauth invalid_grant — reconnection required", permanent: true)

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:errors]
      end

      # A dead designOauth add-on must not take the base Claude login down with it:
      # the adapter says so with permanent: false, and that has to win over the
      # invalid_grant text in the detail.
      test "honours the adapter's permanent flag over the invalid_grant text" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: :error, permanent: false,
                                           detail: "designOauth invalid_grant — reconnection required" })
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.expects(:mark_refresh_error!)
                  .with("designOauth invalid_grant — reconnection required", permanent: false)

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:errors]
      end

      test "marks credential with transient error on non-invalid_grant failure" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: :error, detail: "network timeout" })
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.expects(:mark_refresh_error!).with("network timeout", permanent: false)

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:errors]
      end

      test "clears refresh error on successful refresh when error was present" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: :refreshed, detail: nil })
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.stubs(:refresh_error).returns("previous failure")
        credential.expects(:clear_refresh_error!)

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
      end

      test "skips clear_refresh_error! on success when no prior error" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).returns({ status: :refreshed, detail: nil })
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.stubs(:refresh_error).returns(nil)
        credential.expects(:clear_refresh_error!).never

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
      end

      test "marks credential error when refresh! raises" do
        credential = mock("credential")
        adapter = mock("adapter")
        adapter.stubs(:refresh!).raises(StandardError.new("kaboom"))
        credential.stubs(:id).returns(1)
        credential.stubs(:agent_type).returns("claude_code")
        credential.stubs(:adapter).returns(adapter)
        credential.expects(:mark_refresh_error!).with("kaboom", permanent: false)

        stub_due([ credential ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:errors]
      end
    end
  end
end
