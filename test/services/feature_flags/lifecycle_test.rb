# frozen_string_literal: true

require "test_helper"

# feature_flags:audit and feature_flags:prune, against real rows and the
# in-memory version token.
class FeatureFlags::LifecycleTest < ActiveSupport::TestCase
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  setup do
    @token = FeatureFlags.version_token
    @company = create(:company)
  end

  def empty_registry = FeatureFlags::Registry.new({})

  def lifecycle(registry = FeatureFlags.registry, env: {})
    FeatureFlags::Lifecycle.new(registry: registry, env: FeatureFlags::EnvSource.new(env, registry: registry))
  end

  test "the audit of an empty registry with no rows lists every category as empty" do
    report = lifecycle(empty_registry).report

    assert_predicate report, :empty?
    text = FeatureFlags::Lifecycle.describe(report, today: Date.new(2027, 1, 1))
    [ "Release flags past remove_by: 0", "Same value for every company for 30 days+: 0",
      "Orphaned rows (keys no longer declared; remove with feature_flags:prune): 0",
      "FEATURE_* variables for undeclared keys (remove them from the environment): 0" ].each do |heading|
      assert_includes text, heading
    end
  end

  test "the audit lists all four categories" do
    travel_to Time.zone.local(2027, 1, 1) do
      FeatureFlag.create!(key: "board_ai_summary", enabled: true)
      FeatureFlag.create!(key: "coder_reap", enabled: false)
    end

    registry = FeatureFlags::Registry.new({
      "board_ai_summary" => { "description" => "AI summary panel.", "owner" => "@AixleHQ/board", "kind" => "release",
                              "scope" => "company", "default" => false, "remove_by" => Date.new(2027, 1, 31) }
    })
    report = lifecycle(registry, env: { "FEATURE_OLD_SWITCH" => "on" }).report(today: Date.new(2027, 3, 1))

    assert_equal [ :board_ai_summary ], report.past_remove_by.map(&:key)
    assert_equal [ :board_ai_summary ], report.same_everywhere.map(&:key)
    assert_equal [ "coder_reap" ], report.orphans.map(&:key)
    assert_equal [ "FEATURE_OLD_SWITCH" ], report.undeclared_env

    text = FeatureFlags::Lifecycle.describe(report, today: Date.new(2027, 3, 1))
    assert_includes text, "  board_ai_summary (owner @AixleHQ/board, remove_by 2027-01-31)"
    assert_includes text, "  board_ai_summary = on since 2027-01-01 (owner @AixleHQ/board, decided by global)"
    assert_includes text, "  coder_reap (0 company overrides)"
    assert_includes text, "  FEATURE_OLD_SWITCH"
  end

  test "only release flags are listed as past remove_by, and a recent change is not the same everywhere" do
    travel_to(Time.zone.local(2027, 1, 20)) { FeatureFlag.create!(key: "coder_reap", enabled: false) }
    registry = FeatureFlags::Registry.new({
      "coder_reap" => { "description" => "Reaper.", "owner" => "@AixleHQ/platform", "kind" => "ops",
                        "scope" => "global", "default" => true, "remove_by" => Date.new(2027, 1, 1) }
    })

    report = lifecycle(registry).report(today: Date.new(2027, 2, 1))

    assert_empty report.past_remove_by
    assert_empty report.same_everywhere
  end

  test "an override that differs keeps a flag off the same-everywhere list" do
    travel_to Time.zone.local(2026, 11, 1) do
      FeatureFlag.create!(key: "board_ai_summary", enabled: false).overrides.create!(company: @company, enabled: true, reason: "pilot")
    end

    assert_not_includes lifecycle.report(today: Date.new(2027, 1, 1)).same_everywhere.map(&:key), :board_ai_summary
  end

  test "prune deletes the rows of undeclared keys with one audit each, and is idempotent" do
    board = FeatureFlag.create!(key: "board_ai_summary", enabled: true)
    board.overrides.create!(company: @company, enabled: false, reason: "held back")
    FeatureFlag.create!(key: "coder_reap", enabled: false)
    registry = FeatureFlags::Registry.new({
      "coder_reap" => { "description" => "Reaper.", "owner" => "@AixleHQ/platform", "kind" => "ops",
                        "scope" => "global", "default" => true }
    })

    assert_equal [ "board_ai_summary" ], with_feature_registry(registry) { lifecycle(registry).prune }

    assert_nil FeatureFlag.find_by(key: "board_ai_summary")
    assert_equal 0, FeatureFlagOverride.count
    assert FeatureFlag.find_by(key: "coder_reap"), "a declared key's rows are kept"
    audit = Audit.sole
    assert_equal [ "feature_flag.pruned", FeatureFlags::Lifecycle::PRUNE_REASON, nil ],
                 [ audit.action, audit.comment, audit.user_id ]
    assert_equal [ @company.id ], audit.audited_changes["overrides"].pluck("company_id")
    assert_equal 1, @token.bumps

    assert_empty with_feature_registry(registry) { lifecycle(registry).prune }
    assert_equal 1, Audit.count
    assert_equal 1, @token.bumps
  end
end
