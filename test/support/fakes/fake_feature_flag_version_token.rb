# frozen_string_literal: true

# FeatureFlags::VersionToken without Redis (CI has none): one token shared by
# every store built with it, a count of reads, and an outage switch that makes
# `read` answer nil the way the real token does when Redis is unreachable.
# The contract both satisfy is test/services/feature_flags/version_token_test.rb.
class FakeFeatureFlagVersionToken
  attr_reader :reads
  attr_accessor :unavailable

  def initialize
    @token = nil
    @reads = 0
    @unavailable = false
  end

  def read
    @reads += 1
    unavailable ? nil : @token
  end

  def bump
    return if unavailable

    @token = SecureRandom.uuid
  end
end
