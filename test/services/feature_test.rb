# frozen_string_literal: true

require "test_helper"

class FeatureTest < ActiveSupport::TestCase
  setup { @company = create(:company) }

  test "enabled? resolves the shipped flags through the rows and the ENV layer" do
    refute Feature.enabled?(:external_runners, company: @company)
    assert Feature.enabled?(:coder_reap)

    with_feature(:external_runners, true, company: @company) do
      assert Feature.enabled?(:external_runners, company: @company)
      refute Feature.enabled?(:external_runners, company: nil)
    end
  end

  test "explain reports the winning source and the ENV variable" do
    with_feature(:external_runners, true, company: @company) do
      assert_equal [ true, :company, "FEATURE_EXTERNAL_RUNNERS" ],
                   Feature.explain(:external_runners, company: @company).then { |r| [ r.value, r.source, r.env_var ] }

      stub_feature_env(:external_runners, "off") do
        assert_equal [ false, :env, "FEATURE_EXTERNAL_RUNNERS" ],
                     Feature.explain(:external_runners, company: @company).then { |r| [ r.value, r.source, r.env_var ] }
      end
    end
  end

  test "a flag's own env: variable locks it, and FEATURE_<KEY> wins over it" do
    stub_feature_env(:coder_reap, "false", variable: "CODER_REAP_ENABLED") do
      assert_equal [ false, :env, "CODER_REAP_ENABLED" ], Feature.explain(:coder_reap).then { |r| [ r.value, r.source, r.env_var ] }

      stub_feature_env(:coder_reap, "on") do
        assert_equal [ true, "FEATURE_CODER_REAP" ], Feature.explain(:coder_reap).then { |r| [ r.value, r.env_var ] }
      end
    end
  end

  test "the company: rules hold through the facade" do
    assert_raises(ArgumentError) { Feature.enabled?(:external_runners) }
    assert_raises(ArgumentError) { Feature.enabled?(:coder_reap, company: @company) }
  end

  test "an undeclared key raises in development and test" do
    assert_raises(FeatureFlags::UnknownFlag) { Feature.enabled?(:external_runner, company: nil) }
  end

  test "an undeclared key reads as off and is reported outside development and test" do
    Rails.env.stubs(:local?).returns(false)

    resolution = nil
    assert_error_reported(FeatureFlags::UnknownFlag) do
      resolution = Feature.explain(:external_runner, company: @company)
    end
    assert_equal [ false, :unknown ], [ resolution.value, resolution.source ]
    refute Feature.enabled?(:external_runner)
  end

  test "an undeclared key is reported once per key, and reads as off on every call" do
    Rails.env.stubs(:local?).returns(false)

    reports = capture_error_reports(FeatureFlags::UnknownFlag) do
      3.times { refute Feature.enabled?(:external_runner, company: @company) }
      2.times { assert_equal :unknown, Feature.explain(:old_flag).source }
    end

    assert_equal %w[external_runner old_flag], reports.map { |report| report.context[:flag] }
  end

  # boot! is compose plus installing the result; compose installs nothing, so
  # boot-time validation and reporting are tested on the graph it returns.
  def compose(env: {}, registry_path: FeatureFlags::REGISTRY_PATH)
    FeatureFlags.compose(registry_path: registry_path, env: env)
  end

  # The initializer calls booted: when eager loading (FeaturesResource) has
  # already composed the graph, it is reused and nothing is reported again.
  test "booted reuses the installed graph without composing again" do
    graph = FeatureFlags.booted
    FeatureFlags.expects(:compose).never

    assert_same graph, FeatureFlags.booted
  end

  test "compose warns for each FEATURE_* variable no flag declares, and composes" do
    graph = nil
    reports = capture_error_reports(FeatureFlags::UndeclaredEnv) do
      graph = compose(env: { "FEATURE_OLD_FLAG" => "on", "FEATURE_CODER_REEP" => "1", "FEATURE_CODER_REAP" => "off" })
    end

    assert_equal %w[FEATURE_CODER_REEP FEATURE_OLD_FLAG], reports.map { |report| report.context[:variable] }
    assert_equal [ :warning, FeatureFlags::UNDECLARED_ENV_SOURCE ], [ reports.first.severity, reports.first.source ]
    assert_equal false, graph.env_source.value_for(:coder_reap) # rubocop:disable Minitest/RefuteFalse
  end

  test "compose reads a flag's own env: variable" do
    graph = compose(env: { "CODER_REAP_ENABLED" => "off" })

    assert_equal [ false, "CODER_REAP_ENABLED" ], [ graph.env_source.value_for(:coder_reap), graph.env_source.variable_for(:coder_reap) ]
  end

  test "compose fails on an invalid ENV value for a declared flag, naming the variable" do
    error = assert_raises(FeatureFlags::InvalidEnv) { compose(env: { "FEATURE_CODER_REAP" => "maybe" }) }
    assert_match "FEATURE_CODER_REAP", error.message

    error = assert_raises(FeatureFlags::InvalidEnv) { compose(env: { "CODER_REAP_ENABLED" => "yes" }) }
    assert_match "CODER_REAP_ENABLED", error.message
  end

  test "compose fails on an invalid registry" do
    Tempfile.create([ "feature_flags", ".yml" ]) do |file|
      file.write("coder_reap:\n  description: Reaper\n  kind: ops\n  scope: global\n  default: true\n")
      file.flush

      error = assert_raises(FeatureFlags::InvalidRegistry) { compose(registry_path: file.path) }
      assert_match "coder_reap: missing owner", error.message
    end
  end

  test "compose installs nothing" do
    booted = FeatureFlags.booted
    graph = compose(env: { "FEATURE_CODER_REAP" => "off" })

    assert_equal false, graph.env_source.value_for(:coder_reap) # rubocop:disable Minitest/RefuteFalse
    assert_same booted, FeatureFlags.booted
    assert_nil FeatureFlags.env_source.value_for(:coder_reap)
  end
end
