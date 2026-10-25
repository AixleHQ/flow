# frozen_string_literal: true

require "test_helper"

class FeatureFlags::EnvSourceTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)

  def env(variables) = FeatureFlags::EnvSource.new(variables, registry: REGISTRY)

  def env_with(settings, variables = {}) = FeatureFlags::EnvSource.new(variables, registry: REGISTRY, settings: settings)

  def reap_setting(value) = { coder: { reap_enabled: value } }

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

  test "FEATURE_<KEY> is the variable that locks it" do
    assert_equal "FEATURE_CODER_REAP", env("FEATURE_CODER_REAP" => "off").variable_for(:coder_reap)
    assert_nil env({}).variable_for(:coder_reap)
  end

  # config/settings.yml gives coder.reap_enabled true or false when
  # CODER_REAP_ENABLED is set and nil when it is not.
  test "the legacy env_setting locks the flag only when its variable is set" do
    source = env_with(reap_setting(false))
    assert_equal [ false, "CODER_REAP_ENABLED" ], [ source.value_for(:coder_reap), source.variable_for(:coder_reap) ]

    source = env_with(reap_setting(true))
    assert_equal [ true, "CODER_REAP_ENABLED" ], [ source.value_for(:coder_reap), source.variable_for(:coder_reap) ]

    source = env_with(reap_setting(nil))
    assert_equal [ nil, nil ], [ source.value_for(:coder_reap), source.variable_for(:coder_reap) ]
  end

  test "FEATURE_<KEY> wins over the legacy variable when both are set" do
    [ [ "on", false, true ], [ "off", true, false ], [ "off", false, false ] ].each do |feature, legacy, expected|
      source = env_with(reap_setting(legacy), "FEATURE_CODER_REAP" => feature)

      assert_equal [ expected, "FEATURE_CODER_REAP" ], [ source.value_for(:coder_reap), source.variable_for(:coder_reap) ],
                   "FEATURE_CODER_REAP=#{feature}, coder.reap_enabled=#{legacy}"
    end
  end

  test "string-keyed settings are read too" do
    assert_equal false, env_with({ "coder" => { "reap_enabled" => false } }).value_for(:coder_reap) # rubocop:disable Minitest/RefuteFalse
  end

  test "a legacy setting that is not true, false or unset fails boot naming it and its variable" do
    error = assert_raises(FeatureFlags::InvalidEnv) { env_with(reap_setting("false")) }

    assert_match "coder.reap_enabled (CODER_REAP_ENABLED) must be true, false or unset, got \"false\"", error.message
  end

  test "an env_setting that names no setting fails boot" do
    [ {}, { coder: {} }, { coder: "on" } ].each do |settings|
      error = assert_raises(FeatureFlags::InvalidEnv) { env_with(settings) }

      assert_match "coder_reap: env_setting coder.reap_enabled is not a setting", error.message
    end
  end

  test "without settings no legacy lock is read" do
    assert_nil env({}).value_for(:coder_reap)
  end

  test "merge_settings, merge and with_registry keep the legacy layer" do
    source = env_with(reap_setting(nil)).merge_settings("coder.reap_enabled" => false)

    refute source.value_for(:coder_reap)
    refute source.merge("FEATURE_BOARD_AI_SUMMARY" => "on").value_for(:coder_reap)
    refute source.with_registry(REGISTRY).value_for(:coder_reap)
    assert_equal "FEATURE_CODER_REAP", source.merge("FEATURE_CODER_REAP" => "off").variable_for(:coder_reap)
  end

  # Existing deployments keep their meaning: `true` is on, anything else set is
  # off, and only an unset variable leaves the flag to admin and its default.
  test "config/settings.yml gives coder.reap_enabled a value only when CODER_REAP_ENABLED is set" do
    saved = ENV.fetch("CODER_REAP_ENABLED", nil)

    { nil => nil, "true" => true, "false" => false, "no" => false, "" => false }.each do |raw, expected|
      raw.nil? ? ENV.delete("CODER_REAP_ENABLED") : ENV["CODER_REAP_ENABLED"] = raw
      settings = Config.load_files(Rails.root.join("config/settings.yml"), Rails.root.join("config/settings/test.yml"))
      source = FeatureFlags::EnvSource.new({}, registry: REGISTRY, settings: settings.to_h)

      assert_equal [ expected, expected.nil? ? nil : "CODER_REAP_ENABLED" ],
                   [ source.value_for(:coder_reap), source.variable_for(:coder_reap) ], "CODER_REAP_ENABLED=#{raw.inspect}"
    end
  ensure
    saved.nil? ? ENV.delete("CODER_REAP_ENABLED") : ENV["CODER_REAP_ENABLED"] = saved
  end
end
