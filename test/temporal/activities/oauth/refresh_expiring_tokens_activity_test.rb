# frozen_string_literal: true

require "test_helper"

module Activities
  module Oauth
    # Runs the real activity through the SDK's serverless ActivityEnvironment
    # (docs/testing.md §2). The DB scope (OauthCredential.refresh_due) and the
    # refresh itself (Oauth::TokenService.refresh_credential) are boundaries owned
    # by other builders, so they are stubbed here — this test pins the activity's
    # own behavior: count aggregation, per-record rescue, and the return shape.
    class RefreshExpiringTokensActivityTest < ActiveSupport::TestCase
      def cred_double(id:, status:)
        c = stub(id: id, provider: "mcp:host", refresh_error: "boom")
        ::Oauth::TokenService.stubs(:refresh_credential).with(c).returns(status)
        c
      end

      def stub_due(records)
        records.define_singleton_method(:find_each) { |&blk| each(&blk) }
        ::OauthCredential.stubs(:refresh_due)
          .with(RefreshExpiringTokensActivity::REFRESH_WINDOW)
          .returns(records)
      end

      test "aggregates counts across refreshed / not_needed / error outcomes" do
        stub_due([
          cred_double(id: 1, status: :refreshed),
          cred_double(id: 2, status: :not_needed),
          cred_double(id: 3, status: :error)
        ])

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:not_needed]
        assert_equal 1, result[:errors]
      end

      test "per-record rescue keeps the batch going when one credential raises" do
        bad = stub(id: 9, provider: "mcp:host", refresh_error: nil)
        ::Oauth::TokenService.stubs(:refresh_credential).with(bad).raises(StandardError.new("kaboom"))
        good = cred_double(id: 10, status: :refreshed)

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
