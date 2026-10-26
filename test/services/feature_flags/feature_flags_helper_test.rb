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
      env_before = ENV.to_h
      stub_feature_env(:coder_reap, "off") do
        assert_equal :env, Feature.explain(:coder_reap).source
        assert_equal env_before, ENV.to_h
      end

      assert_equal :default, Feature.explain(:coder_reap).source
      assert_raises(FeatureFlags::InvalidEnv) { stub_feature_env(:coder_reap, "maybe") { flunk } }
    end
  end

  test "stub_feature_env_setting locks a flag through its legacy setting for the block" do
    with_example_flags do
      stub_feature_env_setting(:coder_reap, false) do
        assert_equal [ false, :env, "CODER_REAP_ENABLED" ], Feature.explain(:coder_reap).then { |r| [ r.value, r.source, r.env_var ] }
      end

      assert_equal :default, Feature.explain(:coder_reap).source
      assert_raises(ArgumentError) { stub_feature_env_setting(:board_ai_summary, false) { flunk } }
    end
  end

  test "with_feature_registry swaps the declared flags for the block" do
    with_example_flags { assert FeatureFlags.registry.declared?(:board_ai_summary) }

    refute FeatureFlags.registry.declared?(:board_ai_summary)
  end

  test "with_feature_registry returns what its block returns" do
    assert_equal :done, with_example_flags { :done }
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

  test "the test settings drop FEATURE_* variables from the process environment" do
    saved = ENV.fetch("FEATURE_CODER_REAP", nil)
    ENV["FEATURE_CODER_REAP"] = "off"
    settings = Config.load_files(Rails.root.join("config/settings.yml"), Rails.root.join("config/settings/test.yml"))

    assert_empty settings.feature_flags.env.to_h
  ensure
    saved.nil? ? ENV.delete("FEATURE_CODER_REAP") : ENV["FEATURE_CODER_REAP"] = saved
  end

  test "the suite boots with an empty ENV layer" do
    assert_empty Settings.feature_flags.env.to_h
    assert_empty FeatureFlags.env_source.raw
  end

  test "the suite boots with the test environment's infrastructure" do
    assert_kind_of FeatureFlags::MemoryStore, FeatureFlags.store
    assert_kind_of FakeFeatureFlagVersionToken, FeatureFlags.version_token
  end

  test "nothing can assign the composed graph's parts" do
    %i[registry= env_source= store= version_token=].each do |writer|
      refute_respond_to FeatureFlags, writer
    end
  end

  # Both tests bump the token without cleaning up; whichever runs second still
  # counts from zero, because setup resets it.
  2.times do |run|
    test "every test starts from a fresh version token (#{run + 1})" do
      token = FeatureFlags.version_token
      assert_equal [ 0, 0, false, nil ], [ token.bumps, token.reads, token.unavailable, token.on_bump ]

      token.bump
      token.unavailable = true
      token.on_bump = -> {}
    end
  end

  test "a FEATURE_* lock cannot outlive its block, even when the block raises" do
    with_example_flags do
      assert_raises(RuntimeError) do
        stub_feature_env(:coder_reap, "off") do
          assert_equal :env, Feature.explain(:coder_reap).source
          raise "boom"
        end
      end

      assert_equal :default, Feature.explain(:coder_reap).source
    end
  end

  test "FeatureFlags.with substitutes the registry and the ENV layer, and nests" do
    store = FeatureFlags.store
    token = FeatureFlags.version_token
    shipped = FeatureFlags.registry

    with_example_flags do
      example = FeatureFlags.registry
      refute_same shipped, example

      stub_feature_env(:coder_reap, "off") do
        assert_same example, FeatureFlags.registry, "an ENV substitution keeps the registry"
        assert_equal :env, Feature.explain(:coder_reap).source
        assert_equal [ store, token ], [ FeatureFlags.store, FeatureFlags.version_token ]
      end

      assert_same example, FeatureFlags.registry
      assert_empty FeatureFlags.env_source.raw
    end

    assert_same shipped, FeatureFlags.registry
    assert_raises(ArgumentError) { FeatureFlags.with { flunk } }
    assert_raises(ArgumentError) { FeatureFlags.with(registry: shipped) }
  end

  test "a registry given with an ENV layer gets that layer re-read against it" do
    registry = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)
    env = FeatureFlags::EnvSource.new({ "FEATURE_BOARD_AI_SUMMARY" => "on" }, registry: FeatureFlags::Registry.new({}))
    assert_equal [ "FEATURE_BOARD_AI_SUMMARY" ], env.undeclared

    FeatureFlags.with(registry: registry, env: env) do
      assert_equal [ true, :env ], Feature.explain(:board_ai_summary, company: nil).then { |r| [ r.value, r.source ] }
    end
  end

  test "a substitution is visible on this fiber only, never on another thread" do
    with_example_flags do
      stub_feature_env(:coder_reap, "off") do
        elsewhere = Thread.new { [ FeatureFlags.registry.declared?(:board_ai_summary), FeatureFlags.env_source.raw ] }.value

        assert_equal [ false, {} ], elsewhere
        assert FeatureFlags.registry.declared?(:board_ai_summary)
      end
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
