# frozen_string_literal: true

# FeatureFlags::VersionToken without Redis (CI has none): one token shared by
# every store built with it, a count of reads and bumps, and an outage switch
# that makes `read` answer nil the way the real token does when Redis is
# unreachable. `on_bump` runs at each bump, for a test that asserts what was
# true at that moment (FeatureFlags::Admin bumps only after its commit).
# The contract both satisfy is test/services/feature_flags/version_token_test.rb.
#
# The suite boots FeatureFlags with one instance (test/support/feature_flags_helper.rb)
# and resets it before every test, so a test reads FeatureFlags.version_token.bumps
# and sets `unavailable` / `on_bump` on it instead of installing its own.
class FakeFeatureFlagVersionToken
  attr_reader :reads, :bumps
  attr_accessor :unavailable, :on_bump

  def initialize
    reset!
  end

  def reset!
    @token = nil
    @reads = 0
    @bumps = 0
    @unavailable = false
    @on_bump = nil
  end

  def read
    @reads += 1
    unavailable ? nil : @token
  end

  def bump
    @bumps += 1
    on_bump&.call
    return if unavailable

    @token = SecureRandom.uuid
  end
end
