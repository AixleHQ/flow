# frozen_string_literal: true

require "test_helper"

class FeatureTest < ActiveSupport::TestCase
  setup { @company = Company.new(id: 7) }

  def with_example_flags(&) = with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY, &)

  test "enabled? resolves through the process registry, ENV layer and store" do
    with_example_flags do
      refute Feature.enabled?(:board_ai_summary, company: @company)
      assert Feature.enabled?(:coder_reap)

      with_feature(:board_ai_summary, true, company: @company) do
        assert Feature.enabled?(:board_ai_summary, company: @company)
        refute Feature.enabled?(:board_ai_summary, company: nil)
      end
    end
  end

  test "explain reports the winning source, the ENV variable and the shadowed layers" do
    with_example_flags do
      with_feature(:board_ai_summary, true) do
        with_feature(:board_ai_summary, true, company: @company) do
          stub_feature_env(:board_ai_summary, "off") do
            resolution = Feature.explain(:board_ai_summary, company: @company)

            assert_equal [ false, :env, "FEATURE_BOARD_AI_SUMMARY" ],
                         [ resolution.value, resolution.source, resolution.env_var ]
            assert_equal [ { source: :company, value: true }, { source: :global, value: true } ], resolution.shadowed
          end
        end
      end
    end
  end

  test "the company: rules hold through the facade" do
    with_example_flags do
      assert_raises(ArgumentError) { Feature.enabled?(:board_ai_summary) }
      assert_raises(ArgumentError) { Feature.enabled?(:coder_reap, company: @company) }
    end
  end

  test "an undeclared key raises in development and test" do
    assert_raises(FeatureFlags::UnknownFlag) { Feature.enabled?(:board_ai_summary, company: nil) }
  end

  test "an undeclared key reads as off and is reported outside development and test" do
    Rails.env.stubs(:local?).returns(false)

    resolution = nil
    assert_error_reported(FeatureFlags::UnknownFlag) do
      resolution = Feature.explain(:board_ai_sumary, company: @company)
    end
    assert_equal [ false, :unknown ], [ resolution.value, resolution.source ]
    refute Feature.enabled?(:board_ai_sumary)
  end

  test "an undeclared key is reported once per key, and reads as off on every call" do
    Rails.env.stubs(:local?).returns(false)

    reports = capture_error_reports(FeatureFlags::UnknownFlag) do
      3.times { refute Feature.enabled?(:board_ai_sumary, company: @company) }
      2.times { assert_equal :unknown, Feature.explain(:old_flag).source }
    end

    assert_equal %w[board_ai_sumary old_flag], reports.map { |report| report.context[:flag] }
  end

  test "the shipped registry declares coder_reap, on by default" do
    assert FeatureFlags.registry.declared?(:coder_reap)
    assert Feature.enabled?(:coder_reap)
  end

  def boot!(env: {}, registry_path: FeatureFlagsHelper::EXAMPLE_REGISTRY)
    with_example_flags do
      FeatureFlags.boot!(registry_path: registry_path, env: env, settings: { coder: { reap_enabled: nil } })
    end
  end

  test "boot! warns for each FEATURE_* variable no flag declares, and boots" do
    reports = capture_error_reports(FeatureFlags::UndeclaredEnv) do
      boot!(env: { "FEATURE_OLD_FLAG" => "on", "FEATURE_BOARD_AI_SUMARY" => "1", "FEATURE_CODER_REAP" => "off" })
    end

    assert_equal %w[FEATURE_BOARD_AI_SUMARY FEATURE_OLD_FLAG], reports.map { |report| report.context[:variable] }
    assert_equal [ :warning, FeatureFlags::UNDECLARED_ENV_SOURCE ], [ reports.first.severity, reports.first.source ]
  end

  test "boot! fails on an invalid ENV value for a declared flag" do
    error = assert_raises(FeatureFlags::InvalidEnv) { boot!(env: { "FEATURE_CODER_REAP" => "maybe" }) }

    assert_match "FEATURE_CODER_REAP", error.message
  end

  test "boot! fails on an invalid registry" do
    Tempfile.create([ "feature_flags", ".yml" ]) do |file|
      file.write("coder_reap:\n  description: Reaper\n  kind: ops\n  scope: global\n  default: true\n")
      file.flush

      error = assert_raises(FeatureFlags::InvalidRegistry) { boot!(registry_path: file.path) }
      assert_match "coder_reap: missing owner", error.message
    end
  end

  test "a boot! inside with_feature_registry is undone after the block" do
    boot!

    assert_not FeatureFlags.registry.declared?(:board_ai_summary)
  end

  test "boot! reads the legacy env_setting lock from the settings" do
    with_example_flags do
      FeatureFlags.boot!(registry_path: FeatureFlagsHelper::EXAMPLE_REGISTRY, env: {},
                         settings: { coder: { reap_enabled: false } })

      resolution = Feature.explain(:coder_reap)
      assert_equal [ false, :env, "CODER_REAP_ENABLED" ], [ resolution.value, resolution.source, resolution.env_var ]
    end
  end

  test "boot! fails on a legacy setting that is not true, false or unset" do
    error = assert_raises(FeatureFlags::InvalidEnv) do
      with_example_flags do
        FeatureFlags.boot!(registry_path: FeatureFlagsHelper::EXAMPLE_REGISTRY, env: {},
                           settings: { coder: { reap_enabled: "no" } })
      end
    end

    assert_match "coder.reap_enabled (CODER_REAP_ENABLED) must be true, false or unset", error.message
  end
end
