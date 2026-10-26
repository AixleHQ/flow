# frozen_string_literal: true

require "test_helper"

# The helpers every test uses to set a flag: they must leave no trace on the next test.
class FeatureFlags::FeatureFlagsHelperTest < ActiveSupport::TestCase
  setup { @company = create(:company) }

  test "with_feature sets the global value as a row, for the block only" do
    with_feature(:coder_reap, false) do
      assert_equal :global, Feature.explain(:coder_reap).source
      assert_equal false, FeatureFlag.find_by!(key: "coder_reap").enabled # rubocop:disable Minitest/RefuteFalse
    end

    assert_equal :default, Feature.explain(:coder_reap).source
  end

  test "with_feature(..., company:) sets one company's override" do
    with_feature(:external_runners, true, company: @company) do
      assert Feature.enabled?(:external_runners, company: @company)
      refute Feature.enabled?(:external_runners, company: create(:company))
    end

    refute Feature.enabled?(:external_runners, company: @company)
  end

  test "nested with_feature blocks unwind in order" do
    with_feature(:external_runners, true, company: @company) do
      with_feature(:external_runners, false, company: @company) do
        refute Feature.enabled?(:external_runners, company: @company)
      end

      assert Feature.enabled?(:external_runners, company: @company)
    end
  end

  test "with_feature restores the value when the block raises" do
    assert_raises(RuntimeError) { with_feature(:coder_reap, false) { raise "boom" } }

    assert Feature.enabled?(:coder_reap)
  end

  test "with_feature refuses what the resolver would refuse" do
    assert_raises(FeatureFlags::UnknownFlag) { with_feature(:external_runner, true) { flunk } }
    assert_raises(ArgumentError) { with_feature(:coder_reap, false, company: @company) { flunk } }
    assert_raises(ArgumentError) { with_feature(:external_runners, true, company: nil) { flunk } }
    assert_raises(ArgumentError) { with_feature(:external_runners, "on") { flunk } }
  end

  # Both tests write a row without cleaning up; whichever runs second still
  # starts with none, because the test transaction rolled it back.
  2.times do |run|
    test "every test starts from the declared defaults (#{run + 1})" do
      assert_empty FeatureFlag.load_snapshot
      assert_nil Current.feature_snapshot

      FeatureFlag.create!(key: "coder_reap", enabled: false)
      Feature.enabled?(:coder_reap)
    end
  end

  test "stub_feature_env locks the flag for the block without touching ENV" do
    env_before = ENV.to_h
    stub_feature_env(:coder_reap, "off") do
      assert_equal [ :env, "FEATURE_CODER_REAP" ], Feature.explain(:coder_reap).then { |r| [ r.source, r.env_var ] }
      assert_equal env_before, ENV.to_h
    end

    assert_equal :default, Feature.explain(:coder_reap).source
    assert_raises(FeatureFlags::InvalidEnv) { stub_feature_env(:coder_reap, "maybe") { flunk } }
  end

  test "stub_feature_env simulates a flag's own env: variable" do
    stub_feature_env(:coder_reap, "false", variable: "CODER_REAP_ENABLED") do
      assert_equal [ false, :env, "CODER_REAP_ENABLED" ], Feature.explain(:coder_reap).then { |r| [ r.value, r.source, r.env_var ] }
    end

    assert_equal :default, Feature.explain(:coder_reap).source
    assert_raises(ArgumentError) { stub_feature_env(:external_runners, "on", variable: "CODER_REAP_ENABLED") { flunk } }
  end

  test "a lock cannot outlive its block, even when the block raises" do
    assert_raises(RuntimeError) do
      stub_feature_env(:coder_reap, "off") do
        assert_equal :env, Feature.explain(:coder_reap).source
        raise "boom"
      end
    end

    assert_equal :default, Feature.explain(:coder_reap).source
  end

  test "nested locks unwind in order, and the block's value is returned" do
    result = stub_feature_env(:coder_reap, "off") do
      stub_feature_env(:external_runners, "on") do
        assert_equal [ false, true ], [ Feature.enabled?(:coder_reap), Feature.enabled?(:external_runners, company: nil) ]
      end
      assert_nil FeatureFlags.env_source.value_for(:external_runners)
      :done
    end

    assert_equal :done, result
    assert_empty FeatureFlags.env_source.raw
  end

  test "a lock is visible on this fiber only, never on another thread" do
    stub_feature_env(:coder_reap, "off") do
      assert_equal({}, Thread.new { FeatureFlags.env_source.raw }.value)
      assert_equal :env, Feature.explain(:coder_reap).source
    end
  end

  test "the test settings drop FEATURE_* and env: variables from the process environment" do
    saved = ENV.to_h.slice("FEATURE_CODER_REAP", "CODER_REAP_ENABLED")
    ENV["FEATURE_CODER_REAP"] = "off"
    ENV["CODER_REAP_ENABLED"] = "false"
    settings = Config.load_files(Rails.root.join("config/settings.yml"), Rails.root.join("config/settings/test.yml"))

    assert_empty settings.feature_flags.env.to_h
  ensure
    %w[FEATURE_CODER_REAP CODER_REAP_ENABLED].each { |name| saved.key?(name) ? ENV[name] = saved[name] : ENV.delete(name) }
  end

  test "config/settings.yml collects FEATURE_* variables and the variables flags declare as env:" do
    saved = ENV.to_h.slice("FEATURE_CODER_REAP", "CODER_REAP_ENABLED", "CODER_REAP_CONFIRMATION_MINUTES")
    ENV["FEATURE_CODER_REAP"] = "off"
    ENV["CODER_REAP_ENABLED"] = "false"
    ENV["CODER_REAP_CONFIRMATION_MINUTES"] = "5"
    settings = Config.load_files(Rails.root.join("config/settings.yml"))

    assert_equal({ "FEATURE_CODER_REAP" => "off", "CODER_REAP_ENABLED" => "false" },
                 settings.feature_flags.env.to_h.transform_keys(&:to_s).slice("FEATURE_CODER_REAP", "CODER_REAP_ENABLED", "CODER_REAP_CONFIRMATION_MINUTES"))
    assert_not settings.coder.to_h.key?(:reap_enabled)
  ensure
    %w[FEATURE_CODER_REAP CODER_REAP_ENABLED CODER_REAP_CONFIRMATION_MINUTES].each do |name|
      saved.key?(name) ? ENV[name] = saved[name] : ENV.delete(name)
    end
  end

  test "the suite boots with an empty ENV layer" do
    assert_empty Settings.feature_flags.env.to_h
    assert_empty FeatureFlags.env_source.raw
  end

  test "nothing can assign the composed graph's parts" do
    %i[registry= env_source=].each { |writer| refute_respond_to FeatureFlags, writer }
  end
end
