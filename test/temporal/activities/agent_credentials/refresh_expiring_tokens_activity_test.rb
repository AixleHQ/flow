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
      def stub_due(records)
        records.define_singleton_method(:find_each) { |&blk| each(&blk) }
        refreshable = mock("refreshable_relation")
        refreshable.stubs(:refresh_due)
          .with(RefreshExpiringTokensActivity::REFRESH_WINDOW)
          .returns(records)
        ::AgentCredential.stubs(:refreshable).returns(refreshable)
      end

      test "aggregates counts across refreshed / not_needed / error statuses" do
        stub_due([
          credential_double(id: 1, agent_type: "claude_code", status: :refreshed),
          credential_double(id: 2, agent_type: "claude_code", status: :not_needed),
          credential_double(id: 3, agent_type: "codex", status: :error, detail: "boom")
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
        good = credential_double(id: 10, agent_type: "claude_code", status: :refreshed)

        stub_due([ bad, good ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:errors]
        assert_equal 0, result[:not_needed]
      end

      test "returns zero counts when nothing is due" do
        stub_due([])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal({ refreshed: 0, not_needed: 0, errors: 0 }, result)
      end
    end
  end
end
