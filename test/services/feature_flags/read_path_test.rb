# frozen_string_literal: true

require "test_helper"

# The read path: Rails.cache with a short TTL, memoised in Current for one
# executor run (a request or a job). A test body runs outside any executor run,
# so `in_request` wraps one the way Rails does for every request.
class FeatureFlags::ReadPathTest < ActiveSupport::TestCase
  setup { @admin = create(:user, :super_admin) }

  def in_request(&) = Rails.application.executor.wrap(&)

  def use_cache(cache) = cache.tap { Rails.stubs(:cache).returns(cache) }

  test "a request or job reads the values once, however many checks it makes" do
    use_cache(ActiveSupport::Cache::NullStore.new)
    FeatureFlag.expects(:load_snapshot).twice.returns({})

    in_request { 3.times { assert Feature.enabled?(:coder_reap) } }
    in_request { 3.times { assert Feature.enabled?(:coder_reap) } }
  end

  test "the next request reads the cache, not the database" do
    cache = use_cache(ActiveSupport::Cache::MemoryStore.new)
    FeatureFlag.expects(:load_snapshot).once.returns({})

    in_request { assert Feature.enabled?(:coder_reap) }
    in_request { assert Feature.enabled?(:coder_reap) }
    assert cache.exist?(FeatureFlags::CACHE_KEY)
  end

  test "a write is visible on the next request, in every process" do
    use_cache(ActiveSupport::Cache::MemoryStore.new)

    in_request do
      assert Feature.enabled?(:coder_reap)
      FeatureFlags::Admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
      assert Feature.enabled?(:coder_reap), "one request keeps the values its first check read"
    end

    in_request { refute Feature.enabled?(:coder_reap) }
  end

  test "a change that never dropped the key is visible once the TTL has passed" do
    use_cache(ActiveSupport::Cache::MemoryStore.new)
    in_request { assert Feature.enabled?(:coder_reap) }
    FeatureFlag.create!(key: "coder_reap", enabled: false)

    in_request { assert Feature.enabled?(:coder_reap) }
    travel(FeatureFlags::CACHE_TTL + 1.second) do
      in_request { refute Feature.enabled?(:coder_reap) }
    end
  end

  test "outside an executor run nothing is memoised" do
    use_cache(ActiveSupport::Cache::NullStore.new)
    FeatureFlag.expects(:load_snapshot).twice.returns({})

    assert_not Rails.application.executor.active?
    2.times { assert Feature.enabled?(:coder_reap) }
    assert_nil Current.feature_snapshot
  end
end
