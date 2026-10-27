# frozen_string_literal: true

require "test_helper"

class FeatureFlags::EnvSourceTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.new(
    { "coder_reap" => { "description" => "Reaper.", "owner" => "@AixleHQ/platform", "kind" => "ops", "scope" => "global",
                        "default" => true, "env" => "CODER_REAP_ENABLED" },
      "board_ai_summary" => { "description" => "AI summary.", "owner" => "@AixleHQ/board", "kind" => "release",
                              "scope" => "company", "default" => false, "remove_by" => Date.new(2027, 1, 31) } },
    source: "test registry"
  )

  def env(variables) = FeatureFlags::EnvSource.new(variables, registry: REGISTRY)

  def lock(source, key) = [ source.value_for(key), source.variable_for(key) ]

  test "on, true and 1 are on; off, false and 0 are off; case and whitespace are ignored" do
    { "on" => true, "TRUE" => true, " 1 " => true, "On" => true,
      "off" => false, "False" => false, "0" => false, " OFF\n" => false }.each do |raw, expected|
      assert_equal expected, env("FEATURE_CODER_REAP" => raw).value_for(:coder_reap), raw.inspect
      assert_equal expected, env("CODER_REAP_ENABLED" => raw).value_for(:coder_reap), raw.inspect
    end
  end

  test "unset or empty is not set" do
    assert_nil env({}).value_for(:coder_reap)
    assert_nil env("FEATURE_CODER_REAP" => "").value_for(:coder_reap)
    assert_nil env("CODER_REAP_ENABLED" => "   ").value_for(:coder_reap)
  end

  test "any other value fails with every bad variable named" do
    error = assert_raises(FeatureFlags::InvalidEnv) do
      env("FEATURE_CODER_REAP" => "enabled", "FEATURE_BOARD_AI_SUMMARY" => "maybe", "CODER_REAP_ENABLED" => "no")
    end

    assert_match "FEATURE_CODER_REAP must be on/off/true/false/1/0, got \"enabled\"", error.message
    assert_match "FEATURE_BOARD_AI_SUMMARY must be on/off/true/false/1/0", error.message
    assert_match "CODER_REAP_ENABLED must be on/off/true/false/1/0, got \"no\"", error.message
  end

  test "a FEATURE_* variable for an undeclared key is collected, not raised, whatever its value" do
    source = env("FEATURE_BOARD_AI_SUMARY" => "on", "FEATURE_OLD_FLAG" => "maybe", "FEATURE_CODER_REAP" => "off")

    assert_equal %w[FEATURE_BOARD_AI_SUMARY FEATURE_OLD_FLAG], source.undeclared
    refute source.value_for(:coder_reap)
  end

  test "only the exact upper-case name locks a flag" do
    source = env("FEATURE_coder_reap" => "off", "coder_reap_enabled" => "off")

    assert_nil source.value_for(:coder_reap)
    assert_equal %w[FEATURE_coder_reap], source.undeclared
  end

  test "unrelated variables are neither flags nor reported" do
    source = env("HOME" => "/root", "BOARD_AI_SUMMARY_ENABLED" => "on")

    assert_empty source.undeclared
    assert_nil source.value_for(:board_ai_summary)
  end

  test "reads the settings shape, symbol keys included" do
    assert env(FEATURE_CODER_REAP: "on").value_for("coder_reap")
    refute env(CODER_REAP_ENABLED: "off").value_for("coder_reap")
  end

  test "each variable names itself as the lock" do
    assert_equal [ false, "FEATURE_CODER_REAP" ], lock(env("FEATURE_CODER_REAP" => "off"), :coder_reap)
    assert_equal [ false, "CODER_REAP_ENABLED" ], lock(env("CODER_REAP_ENABLED" => "off"), :coder_reap)
    assert_equal [ nil, nil ], lock(env({}), :coder_reap)
  end

  test "FEATURE_<KEY> wins over the flag's own env: variable when both are set" do
    [ %w[on false], %w[off true], %w[off false] ].each do |feature, own|
      source = env("FEATURE_CODER_REAP" => feature, "CODER_REAP_ENABLED" => own)

      assert_equal [ feature == "on", "FEATURE_CODER_REAP" ], lock(source, :coder_reap),
                   "FEATURE_CODER_REAP=#{feature}, CODER_REAP_ENABLED=#{own}"
    end
  end

  test "merge replaces variables and validates against the same registry" do
    source = env("FEATURE_CODER_REAP" => "off").merge("FEATURE_CODER_REAP" => "on")
    assert source.value_for(:coder_reap)

    source = source.merge("FEATURE_CODER_REAP" => "", "CODER_REAP_ENABLED" => "off")
    assert_equal [ false, "CODER_REAP_ENABLED" ], lock(source, :coder_reap)
    assert_raises(FeatureFlags::InvalidEnv) { source.merge("CODER_REAP_ENABLED" => "maybe") }
  end
end
