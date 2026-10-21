# frozen_string_literal: true

require "test_helper"

# What FeatureFlags::Store relies on from a version token, held to the real
# Redis-backed one and to FakeFeatureFlagVersionToken alike.
module FeatureFlagVersionTokenContract
  extend ActiveSupport::Concern

  included do
    test "there is no token before the first bump" do
      assert_nil token.read
    end

    test "every reader sees a bump, and each bump is a new token" do
      first = token.bump

      assert_equal [ first, first ], [ token.read, other_reader.read ]
      second = token.bump
      assert_not_equal first, second
      assert_equal second, other_reader.read
    end

    test "while unavailable, read and bump answer nil" do
      token.bump
      down = unavailable_token

      assert_nil down.read
      assert_nil down.bump
    end
  end
end

# Needs a reachable Redis (the development stack has one); CI has none, so
# there the real token's available half is skipped and only the fake runs it.
class FeatureFlags::VersionTokenTest < ActiveSupport::TestCase
  include FeatureFlagVersionTokenContract

  UNREACHABLE_URL = "redis://127.0.0.1:1/0"

  setup do
    @key = "feature_flags:version:test:#{SecureRandom.hex(8)}"
    skip "no Redis at #{Settings.redis.url}" unless redis_reachable?
  end

  teardown { redis&.del(@key) }

  def token = @token ||= FeatureFlags::VersionToken.new(key: @key)
  def other_reader = FeatureFlags::VersionToken.new(key: @key)
  def unavailable_token = FeatureFlags::VersionToken.new(url: UNREACHABLE_URL, key: @key)

  def redis = @redis ||= Redis.new(url: Settings.redis.url, connect_timeout: 0.25, reconnect_attempts: 0)

  def redis_reachable?
    redis.ping == "PONG"
  rescue Redis::BaseError
    @redis = nil
    false
  end
end

# The real token with Redis unreachable: runs everywhere, CI included.
class FeatureFlags::UnreachableVersionTokenTest < ActiveSupport::TestCase
  test "an unreachable Redis reads as no token and a failed bump is reported, never raised" do
    token = FeatureFlags::VersionToken.new(url: FeatureFlags::VersionTokenTest::UNREACHABLE_URL)

    assert_nil token.read
    report = capture_error_reports(Redis::BaseError) { assert_nil token.bump }.sole
    assert_equal [ FeatureFlags::VERSION_BUMP_FAILED_SOURCE, :warning ], [ report.source, report.severity ]
  end
end

class FakeFeatureFlagVersionTokenTest < ActiveSupport::TestCase
  include FeatureFlagVersionTokenContract

  def token = @token ||= FakeFeatureFlagVersionToken.new
  def other_reader = token

  def unavailable_token
    token.unavailable = true
    token
  end
end
