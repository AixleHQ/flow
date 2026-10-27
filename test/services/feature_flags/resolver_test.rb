# frozen_string_literal: true

require "test_helper"

# Precedence: ENV > company override > global value > declared default, for a
# flag unknown to one layer or another.
class FeatureFlags::ResolverTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.new(
    { "board_ai_summary" => { "description" => "AI summary.", "owner" => "@AixleHQ/board", "kind" => "release",
                              "scope" => "company", "default" => false, "remove_by" => Date.new(2027, 1, 31) },
      "coder_reap" => { "description" => "Reaper.", "owner" => "@AixleHQ/platform", "kind" => "ops", "scope" => "global",
                        "default" => true, "env" => "CODER_REAP_ENABLED" } },
    source: "test registry"
  )

  # `flags` is FeatureFlag.load_snapshot's shape.
  def resolver(env: {}, flags: {})
    FeatureFlags::Resolver.new(registry: REGISTRY, env: FeatureFlags::EnvSource.new(env, registry: REGISTRY), snapshot: flags)
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
    test "example #{example}: board_ai_summary" do
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

  test "the ENV lock names its variable; without one, env_var is FEATURE_<KEY>" do
    resolver = resolver(env: { "FEATURE_BOARD_AI_SUMMARY" => "off" },
                        flags: { board_ai_summary: { global: true, overrides: { 7 => true } } })

    assert_equal [ :env, "FEATURE_BOARD_AI_SUMMARY" ], board_ai_summary(resolver, 7).then { |r| [ r.source, r.env_var ] }
    assert_equal [ :company, "FEATURE_BOARD_AI_SUMMARY" ],
                 board_ai_summary(resolver(flags: { board_ai_summary: { overrides: { 7 => true } } }), 7).then { |r| [ r.source, r.env_var ] }
  end

  test "an unrecognised ENV value fails boot naming the variable" do
    error = assert_raises(FeatureFlags::InvalidEnv) { resolver(env: { "FEATURE_BOARD_AI_SUMMARY" => "maybe" }) }

    assert_match "FEATURE_BOARD_AI_SUMMARY must be on/off/true/false/1/0", error.message
  end

  test "an unset global flag is its default" do
    resolution = resolver.resolve(:coder_reap)

    assert resolution.value
    assert_equal :default, resolution.source
  end

  test "an admin pauses the reaper at runtime" do
    resolution = resolver(flags: { coder_reap: { global: false } }).resolve(:coder_reap)

    refute resolution.value
    assert_equal :global, resolution.source
  end

  test "a global flag refuses company:" do
    error = assert_raises(ArgumentError) { resolver.resolve(:coder_reap, company: company(7)) }
    assert_match "global", error.message
    assert_raises(ArgumentError) { resolver.resolve(:coder_reap, company: nil) }
  end

  test "a company-scoped flag without company: raises" do
    error = assert_raises(ArgumentError) { resolver.resolve(:board_ai_summary) }

    assert_match "company-scoped", error.message
  end

  test "a declared flag with no runtime value and no ENV is its declared default" do
    resolution = board_ai_summary(resolver, 7)

    assert_equal [ false, :default ], [ resolution.value, resolution.source ]
  end

  test "a global value of nil (use default) is skipped" do
    resolution = board_ai_summary(resolver(flags: { board_ai_summary: { global: nil } }), nil)

    assert_equal :default, resolution.source
  end

  test "runtime values for an undeclared key are ignored, and the key stays unknown" do
    resolver = resolver(flags: { board_ai_sumary: { global: true, overrides: { 7 => true } } })

    assert_equal :default, board_ai_summary(resolver, 7).source
    assert_raises(FeatureFlags::UnknownFlag) { resolver.resolve(:board_ai_sumary, company: company(7)) }
  end

  test "an override left on a global flag is ignored" do
    resolution = resolver(flags: { coder_reap: { overrides: { 7 => false } } }).resolve(:coder_reap)

    assert resolution.value
    assert_equal :default, resolution.source
  end

  test "an undeclared key raises UnknownFlag" do
    error = assert_raises(FeatureFlags::UnknownFlag) { resolver.resolve(:board_ai_sumary, company: nil) }

    assert_equal :board_ai_sumary, error.key
  end

  test "string keys resolve like symbols" do
    assert_equal :coder_reap, resolver.resolve("coder_reap").key
  end

  test "a flag's own env: variable locks it over a global value, naming its variable" do
    resolution = resolver(env: { "CODER_REAP_ENABLED" => "off" }, flags: { coder_reap: { global: true } }).resolve(:coder_reap)
    assert_equal [ false, :env, "CODER_REAP_ENABLED" ], [ resolution.value, resolution.source, resolution.env_var ]

    resolution = resolver(flags: { coder_reap: { global: false } }).resolve(:coder_reap)
    assert_equal [ false, :global, "FEATURE_CODER_REAP" ], [ resolution.value, resolution.source, resolution.env_var ]
  end
end
