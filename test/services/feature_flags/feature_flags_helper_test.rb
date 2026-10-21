# frozen_string_literal: true

require "test_helper"

# The helpers every test uses to set a flag: they must leave no trace on the next test.
class FeatureFlags::FeatureFlagsHelperTest < ActiveSupport::TestCase
  setup { @company = Company.new(id: 7) }

  def with_example_flags(&) = with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY, &)

  test "with_feature sets the global value for the block only" do
    with_example_flags do
      with_feature(:coder_reap, false) { assert_equal :global, Feature.explain(:coder_reap).source }

      assert_equal :default, Feature.explain(:coder_reap).source
    end
  end

  test "with_feature(..., company:) sets one company's override" do
    with_example_flags do
      with_feature(:board_ai_summary, true, company: @company) do
        assert Feature.enabled?(:board_ai_summary, company: @company)
        refute Feature.enabled?(:board_ai_summary, company: Company.new(id: 42))
      end

      refute Feature.enabled?(:board_ai_summary, company: @company)
    end
  end

  test "with_feature restores the store when the block raises" do
    with_example_flags do
      assert_raises(RuntimeError) { with_feature(:coder_reap, false) { raise "boom" } }

      assert Feature.enabled?(:coder_reap)
    end
  end

  test "with_feature refuses what the resolver would refuse" do
    with_example_flags do
      assert_raises(FeatureFlags::UnknownFlag) { with_feature(:board_ai_sumary, true) { flunk } }
      assert_raises(ArgumentError) { with_feature(:coder_reap, false, company: @company) { flunk } }
      assert_raises(ArgumentError) { with_feature(:board_ai_summary, true, company: nil) { flunk } }
      assert_raises(ArgumentError) { with_feature(:board_ai_summary, "on") { flunk } }
    end
  end

  test "stub_feature_env locks the flag for the block without touching ENV" do
    with_example_flags do
      stub_feature_env(:coder_reap, "off") do
        assert_equal :env, Feature.explain(:coder_reap).source
        assert_nil ENV.fetch("FEATURE_CODER_REAP", nil)
      end

      assert_equal :default, Feature.explain(:coder_reap).source
      assert_raises(FeatureFlags::InvalidEnv) { stub_feature_env(:coder_reap, "maybe") { flunk } }
    end
  end

  test "with_feature_registry swaps the declared flags for the block" do
    with_example_flags { assert FeatureFlags.registry.declared?(:coder_reap) }

    refute FeatureFlags.registry.declared?(:coder_reap)
  end

  # Both tests write to the store without cleaning up; whichever runs second
  # still starts empty, because setup resets it.
  2.times do |run|
    test "every test starts from an empty store (#{run + 1})" do
      assert_same FeatureFlags::Snapshot::EMPTY, FeatureFlags.store.snapshot

      FeatureFlags.store.set_global(:coder_reap, false)
      FeatureFlags.store.set_override(:board_ai_summary, 7, true)
    end
  end

  test "the memory store writes and removes values" do
    store = FeatureFlags::MemoryStore.new
    store.set_global(:coder_reap, false)
    store.set_override(:board_ai_summary, 7, true)
    store.set_override(:board_ai_summary, 42, false)
    store.remove_override(:board_ai_summary, 42)
    store.clear_global(:coder_reap)

    assert_equal({ coder_reap: { global: nil, overrides: {} }, board_ai_summary: { global: nil, overrides: { 7 => true } } },
                 store.snapshot.to_h)
    assert_predicate store.snapshot.to_h, :frozen?
  end
end
