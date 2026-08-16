# frozen_string_literal: true

require "test_helper"

module Agents
  class SubscriptionUsageServiceTest < ActiveSupport::TestCase
    # Stands in for a vendor adapter. The HTTP call itself is contract-tested in
    # ClaudeCodeAdapterTest; what matters here is how often the service asks.
    class CountingAdapter
      attr_reader :calls

      def initialize(result)
        @result = result
        @calls = 0
      end

      def fetch_subscription_usage(_credentials)
        @calls += 1
        @result
      end
    end

    OK_USAGE = {
      status: "ok",
      windows: [ { key: "five_hour", utilization: 33.0, resets_at: "2026-08-16T18:00:00+00:00" } ],
      extra_usage: nil
    }.freeze

    setup do
      # The test env's cache is :null_store (writes are no-ops, reads return nil),
      # which would make every render look like a cache miss — so stub a live
      # MemoryStore, as the OAuth state test does.
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)

      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @membership = CompanyMembership.find_by!(user: @user, company: @company)
      @credential = create(:agent_credential, :claude_code, user: @user, company: @company)
    end

    # A fresh membership per call, as a real request gets one: the credential list
    # is memoized on the instance, so reusing one would hide a stale cache key.
    def build_service(adapter, force: false)
      SubscriptionUsageService.new(
        membership: CompanyMembership.find(@membership.id),
        force: force,
        adapter_resolver: ->(_type) { adapter }
      )
    end

    test "returns nothing for a super admin, who has no membership and no credentials" do
      assert_equal [], SubscriptionUsageService.new(membership: nil).call
    end

    test "returns one entry per credential that reports windows, tagged with its agent type" do
      entries = build_service(CountingAdapter.new(OK_USAGE)).call

      assert_equal 1, entries.size
      assert_equal "claude_code", entries.first[:agent_type]
      assert_equal "ok", entries.first[:status]
      assert_equal [ "five_hour" ], entries.first[:windows].map { |w| w[:key] }
      assert_kind_of Time, entries.first[:fetched_at]
    end

    test "drops a credential whose adapter reports no subscription windows" do
      assert_equal [], build_service(CountingAdapter.new(nil)).call
    end

    test "serves repeat renders from the cache instead of re-asking the vendor" do
      adapter = CountingAdapter.new(OK_USAGE)

      3.times { build_service(adapter).call }

      assert_equal 1, adapter.calls
    end

    test "a re-authenticated credential is re-read rather than served from the old cache" do
      adapter = CountingAdapter.new(OK_USAGE)
      build_service(adapter).call

      travel_to 1.second.from_now do
        @credential.touch # what a re-auth or a token refresh does
        build_service(adapter).call
      end

      assert_equal 2, adapter.calls
    end

    test "a failure is cached only briefly so the panel recovers on its own" do
      adapter = CountingAdapter.new({ status: "unavailable" })
      build_service(adapter).call

      travel_to (SubscriptionUsageService::ERROR_TTL + 1.second).from_now do
        build_service(adapter).call
      end

      assert_equal 2, adapter.calls
    end

    test "the refresh button re-reads once the throttle window has passed" do
      adapter = CountingAdapter.new(OK_USAGE)
      build_service(adapter).call

      travel_to (SubscriptionUsageService::MIN_REFRESH_INTERVAL + 1.second).from_now do
        build_service(adapter, force: true).call
      end

      assert_equal 2, adapter.calls
    end

    test "the refresh button cannot be used to hammer the vendor endpoint" do
      adapter = CountingAdapter.new(OK_USAGE)
      build_service(adapter).call

      5.times { build_service(adapter, force: true).call }

      assert_equal 1, adapter.calls
    end

    test "one broken credential does not take the whole panel down" do
      exploding = Class.new do
        def fetch_subscription_usage(_credentials) = raise(ActiveSupport::MessageEncryptor::InvalidMessage)
      end.new

      assert_equal [], build_service(exploding).call
    end
  end
end
