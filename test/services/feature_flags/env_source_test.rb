# frozen_string_literal: true

require "test_helper"

class FeatureFlags::EnvSourceTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)

  def env(variables) = FeatureFlags::EnvSource.new(variables, registry: REGISTRY)

  test "on, true and 1 are on; off, false and 0 are off; case and whitespace are ignored" do
    { "on" => true, "TRUE" => true, " 1 " => true, "On" => true,
      "off" => false, "False" => false, "0" => false, " OFF\n" => false }.each do |raw, expected|
      assert_equal expected, env("FEATURE_CODER_REAP" => raw).value_for(:coder_reap), raw.inspect
    end
  end

  test "unset or empty is not set" do
    assert_nil env({}).value_for(:coder_reap)
    assert_nil env("FEATURE_CODER_REAP" => "").value_for(:coder_reap)
    assert_nil env("FEATURE_CODER_REAP" => "   ").value_for(:coder_reap)
  end

  test "any other value fails with every bad variable named" do
    error = assert_raises(FeatureFlags::InvalidEnv) do
      env("FEATURE_CODER_REAP" => "enabled", "FEATURE_BOARD_AI_SUMMARY" => "maybe")
    end

    assert_match "FEATURE_CODER_REAP must be on/off/true/false/1/0, got \"enabled\"", error.message
    assert_match "FEATURE_BOARD_AI_SUMMARY must be on/off/true/false/1/0", error.message
  end

  test "a variable for an undeclared key is collected, not raised, whatever its value" do
    source = env("FEATURE_BOARD_AI_SUMARY" => "on", "FEATURE_OLD_FLAG" => "maybe", "FEATURE_CODER_REAP" => "off")

    assert_equal %w[FEATURE_BOARD_AI_SUMARY FEATURE_OLD_FLAG], source.undeclared
    refute source.value_for(:coder_reap)
    assert_nil source.value_for(:board_ai_sumary)
  end

  test "only the exact upper-case name locks a flag" do
    source = env("FEATURE_coder_reap" => "off")

    assert_nil source.value_for(:coder_reap)
    assert_equal %w[FEATURE_coder_reap], source.undeclared
  end

  test "the system's own FEATURE_FLAGS_* settings and unrelated variables are not flags" do
    source = env("FEATURE_FLAGS_REFRESH_INTERVAL" => "5", "HOME" => "/root", "CODER_REAP_ENABLED" => "false")

    assert_empty source.undeclared
    assert_empty source.raw
  end

  test "reads the settings shape, symbol keys included" do
    assert env(FEATURE_CODER_REAP: "on").value_for("coder_reap")
  end

  test "the settings block carries FEATURE_* variables and the refresh knobs" do
    settings = Settings.feature_flags

    assert_kind_of Hash, settings.env.to_h
    assert_equal 5, settings.refresh_interval_seconds
    assert_equal 60, settings.max_staleness_seconds
  end

  test "merge replaces variables and validates against the same registry" do
    source = env("FEATURE_CODER_REAP" => "off").merge("FEATURE_CODER_REAP" => "on")

    assert source.value_for(:coder_reap)
    assert_raises(FeatureFlags::InvalidEnv) { source.merge("FEATURE_CODER_REAP" => "maybe") }
  end
end
