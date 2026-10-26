# frozen_string_literal: true

require "test_helper"

# The read path: Rails.cache with a short TTL, memoised in Current for one
# request or job. A test runs inside one executor run, so `Current.reset` stands
# in for the next request, as the executor resets Current between runs.
class FeatureFlags::ReadPathTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    @admin = create(:user, :super_admin)
  end

  def next_request = Current.reset

  test "a request reads the values once, however many checks it makes" do
    assert_queries_count(2) { Feature.enabled?(:coder_reap) }
    assert_queries_count(0) { 3.times { Feature.enabled?(:coder_reap) } }

    next_request
    assert_queries_count(0) { Feature.enabled?(:coder_reap) }
    assert @cache.exist?(FeatureFlags::CACHE_KEY)
  end

  test "a write is visible on the next request, in every process" do
    assert Feature.enabled?(:coder_reap)

    FeatureFlags::Admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
    assert Feature.enabled?(:coder_reap), "one request keeps the values its first check read"

    next_request
    refute Feature.enabled?(:coder_reap)
  end

  test "a change that never dropped the key is visible once the TTL has passed" do
    assert Feature.enabled?(:coder_reap)
    FeatureFlag.create!(key: "coder_reap", enabled: false)

    next_request
    assert Feature.enabled?(:coder_reap)

    travel FeatureFlags::CACHE_TTL + 1.second do
      next_request
      refute Feature.enabled?(:coder_reap)
    end
  end

  test "outside an executor run nothing is memoised" do
    Rails.application.executor.stubs(:active?).returns(false)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::NullStore.new)

    assert_queries_count(4) { 2.times { Feature.enabled?(:coder_reap) } }
    assert_nil Current.feature_snapshot
  end
end
