# frozen_string_literal: true

require "test_helper"

# The resolution model of the feature flags design: the §3.3 table (a flag
# unknown to one layer) and the eleven worked examples of §3.4.
class FeatureFlags::ResolverTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)

  def resolver(env: {}, flags: {}, settings: nil)
    FeatureFlags::Resolver.new(registry: REGISTRY,
                               env: FeatureFlags::EnvSource.new(env, registry: REGISTRY, settings: settings),
                               snapshot: FeatureFlags::Snapshot.new(flags))
  end

  def company(id) = Company.new(id: id)

  def board_ai_summary(resolver, company_id)
    resolver.resolve(:board_ai_summary, company: company_id && company(company_id))
  end

  # [example, ENV, global, overrides, results for 7/42/99/nil, deciding source for 7/42/99/nil]
  BOARD_AI_SUMMARY_EXAMPLES = [
    [ 1, nil,   :no_row, {},              [ false, false, false, false ], %i[default default default default] ],
    [ 2, nil,   true,    {},              [ true,  true,  true,  true  ], %i[global global global global] ],
    [ 3, nil,   true,    { 42 => false }, [ true,  false, true,  true  ], %i[global company global global] ],
    [ 4, nil,   false,   { 7 => true },   [ true,  false, false, false ], %i[company global global global] ],
    [ 5, "off", true,    { 7 => true },   [ false, false, false, false ], %i[env env env env] ],
    [ 6, "on",  :no_row, { 42 => false }, [ true,  true,  true,  true  ], %i[env env env env] ],
    [ 7, nil,   nil,     { 7 => true },   [ true,  false, false, false ], %i[company default default default] ]
  ].freeze

  BOARD_AI_SUMMARY_EXAMPLES.each do |example, env, global, overrides, results, sources|
    test "§3.4 example #{example}: board_ai_summary" do
      flag = { overrides: overrides }
      flag[:global] = global unless global == :no_row
      resolver = resolver(env: env ? { "FEATURE_BOARD_AI_SUMMARY" => env } : {}, flags: { board_ai_summary: flag })

      [ 7, 42, 99, nil ].zip(results, sources).each do |company_id, value, source|
        resolution = board_ai_summary(resolver, company_id)
        assert_equal value, resolution.value, "example #{example}, company #{company_id.inspect}"
        assert_equal source, resolution.source, "example #{example}, company #{company_id.inspect}"
      end
    end
  end

  test "§3.4 example 5: the ENV lock lists the override and global value it shadows" do
    resolver = resolver(env: { "FEATURE_BOARD_AI_SUMMARY" => "off" },
                        flags: { board_ai_summary: { global: true, overrides: { 7 => true } } })

    resolution = board_ai_summary(resolver, 7)

    assert_equal "FEATURE_BOARD_AI_SUMMARY", resolution.env_var
    assert_equal [ { source: :company, value: true }, { source: :global, value: true } ], resolution.shadowed
    assert_equal [ { source: :global, value: true } ], board_ai_summary(resolver, 42).shadowed
  end

  test "§3.4 example 6: ENV beats the off override for 42" do
    resolver = resolver(env: { "FEATURE_BOARD_AI_SUMMARY" => "on" },
                        flags: { board_ai_summary: { overrides: { 42 => false } } })

    assert_equal [ { source: :company, value: false } ], board_ai_summary(resolver, 42).shadowed
  end

  test "§3.4 example 8: an unrecognised ENV value fails boot naming the variable" do
    error = assert_raises(FeatureFlags::InvalidEnv) { resolver(env: { "FEATURE_BOARD_AI_SUMMARY" => "maybe" }) }

    assert_match "FEATURE_BOARD_AI_SUMMARY must be on/off/true/false/1/0", error.message
  end

  test "§3.4 example 9: an unset global flag is its default" do
    resolution = resolver.resolve(:coder_reap)

    assert resolution.value
    assert_equal :default, resolution.source
  end

  test "§3.4 example 10: an admin pauses the reaper at runtime" do
    resolution = resolver(flags: { coder_reap: { global: false } }).resolve(:coder_reap)

    refute resolution.value
    assert_equal :global, resolution.source
  end

  test "§3.4 example 11: a global flag refuses company:" do
    error = assert_raises(ArgumentError) { resolver.resolve(:coder_reap, company: company(7)) }
    assert_match "global", error.message
    assert_raises(ArgumentError) { resolver.resolve(:coder_reap, company: nil) }
  end

  test "a company-scoped flag without company: raises" do
    error = assert_raises(ArgumentError) { resolver.resolve(:board_ai_summary) }

    assert_match "company-scoped", error.message
  end

  test "§3.3: a declared flag with no runtime value and no ENV is its declared default" do
    resolution = board_ai_summary(resolver, 7)

    assert_equal [ false, :default, [] ], [ resolution.value, resolution.source, resolution.shadowed ]
  end

  test "§3.3: a global value of nil (use default) is skipped" do
    resolution = board_ai_summary(resolver(flags: { board_ai_summary: { global: nil } }), nil)

    assert_equal :default, resolution.source
  end

  test "§3.3: runtime values for an undeclared key are ignored, and the key stays unknown" do
    resolver = resolver(flags: { board_ai_sumary: { global: true, overrides: { 7 => true } } })

    assert_equal :default, board_ai_summary(resolver, 7).source
    assert_raises(FeatureFlags::UnknownFlag) { resolver.resolve(:board_ai_sumary, company: company(7)) }
  end

  test "§3.3: an override left on a global flag is ignored" do
    resolution = resolver(flags: { coder_reap: { overrides: { 7 => false } } }).resolve(:coder_reap)

    assert resolution.value
    assert_equal :default, resolution.source
  end

  test "§3.3: an undeclared key raises UnknownFlag" do
    error = assert_raises(FeatureFlags::UnknownFlag) { resolver.resolve(:board_ai_sumary, company: nil) }

    assert_equal :board_ai_sumary, error.key
  end

  test "string keys resolve like symbols" do
    assert_equal :coder_reap, resolver.resolve("coder_reap").key
  end

  test "the legacy env_setting locks coder_reap over a global value, naming its variable" do
    global_on = { coder_reap: { global: true } }

    resolution = resolver(flags: global_on, settings: { coder: { reap_enabled: false } }).resolve(:coder_reap)
    assert_equal [ false, :env, "CODER_REAP_ENABLED" ], [ resolution.value, resolution.source, resolution.env_var ]
    assert_equal [ { source: :global, value: true } ], resolution.shadowed

    resolution = resolver(flags: { coder_reap: { global: false } }, settings: { coder: { reap_enabled: nil } }).resolve(:coder_reap)
    assert_equal [ false, :global, "FEATURE_CODER_REAP" ], [ resolution.value, resolution.source, resolution.env_var ]
  end
end
