# frozen_string_literal: true

require "test_helper"

class FeatureFlags::OverviewTest < ActiveSupport::TestCase
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  setup { @company = create(:company) }

  # An overview of a registry that declares nothing, built directly: the
  # registry is a constructor argument, so no test registry is installed.
  def empty_overview
    registry = FeatureFlags::Registry.new({})
    FeatureFlags::Overview.new(registry: registry, env: FeatureFlags::EnvSource.new({}, registry: registry))
  end

  test "with no flags declared there is nothing to list" do
    assert_empty empty_overview.rows
  end

  test "a flag with no rows resolves to its declared default" do
    rows = FeatureFlags::Overview.new.rows.index_by(&:key)

    assert_equal [ :board_ai_summary, :coder_reap ], rows.keys
    assert_equal [ false, :default, nil, 0, 0 ],
                 rows[:board_ai_summary].then { |row| [ row.resolution.value, row.resolution.source, row.global, row.overrides_on, row.overrides_off ] }
    assert_equal [ true, :default ], [ rows[:coder_reap].resolution.value, rows[:coder_reap].resolution.source ]
  end

  # Read from the rows, not this process's snapshot, which the suite's memory
  # store keeps empty.
  test "values, ENV locks and override counts come from the committed rows" do
    flag = FeatureFlag.create!(key: "board_ai_summary", enabled: true)
    flag.overrides.create!(company: @company, enabled: false, reason: "held back")
    flag.overrides.create!(company: create(:company), enabled: true, reason: "pilot")

    stub_feature_env(:coder_reap, "off") do
      rows = FeatureFlags::Overview.new.rows.index_by(&:key)

      assert_equal [ true, :global, 1, 1 ],
                   rows[:board_ai_summary].then { |row| [ row.resolution.value, row.resolution.source, row.overrides_on, row.overrides_off ] }
      assert rows[:coder_reap].locked?
      assert_equal [ false, :env ], [ rows[:coder_reap].resolution.value, rows[:coder_reap].resolution.source ]
    end
  end

  test "a release flag past its remove-by date is flagged" do
    row = FeatureFlags::Overview.new.row(:board_ai_summary)

    assert_not row.past_remove_by?(Date.new(2027, 1, 31))
    assert row.past_remove_by?(Date.new(2027, 2, 1))
    assert_not FeatureFlags::Overview.new.row(:coder_reap).past_remove_by?(Date.new(2099, 1, 1))
  end

  test "a flag is the same everywhere once no override has differed for 30 days" do
    travel_to Time.zone.local(2027, 1, 1) do
      flag = FeatureFlag.create!(key: "board_ai_summary", enabled: true)
      flag.overrides.create!(company: @company, enabled: false, reason: "held back")
      assert_not FeatureFlags::Overview.new.row(:board_ai_summary).same_everywhere_long?(Date.new(2027, 3, 1))

      flag.overrides.delete_all
      flag.touch
    end

    row = FeatureFlags::Overview.new.row(:board_ai_summary)
    assert_equal Date.new(2027, 1, 1), row.same_everywhere_since
    assert_not row.same_everywhere_long?(Date.new(2027, 1, 30))
    assert row.same_everywhere_long?(Date.new(2027, 1, 31))
  end

  test "with no row, a flag has had its default since it was introduced" do
    row = FeatureFlags::Overview.new.row(:board_ai_summary)

    assert_equal Date.new(2026, 11, 3), row.same_everywhere_since
    assert_nil FeatureFlags::Overview.new.row(:coder_reap).same_everywhere_since
  end

  test "rows of keys no flag declares are orphans" do
    FeatureFlag.create!(key: "board_ai_summary", enabled: true).overrides.create!(company: @company, enabled: true, reason: "pilot")

    orphans = empty_overview.orphans

    assert_equal [ [ "board_ai_summary", 1 ] ], orphans.map { |orphan| [ orphan.key, orphan.overrides_count ] }
    assert_empty FeatureFlags::Overview.new.orphans
  end

  test "a row names the variable that locks it, or every variable that could" do
    rows = FeatureFlags::Overview.new.rows.index_by(&:key)
    assert_nil rows[:coder_reap].env_variable
    assert_equal %w[FEATURE_CODER_REAP CODER_REAP_ENABLED], rows[:coder_reap].env_vars

    stub_feature_env_setting(:coder_reap, false) do
      row = FeatureFlags::Overview.new.row(:coder_reap)

      assert row.locked?
      assert_equal [ "CODER_REAP_ENABLED", %w[CODER_REAP_ENABLED] ], [ row.env_variable, row.env_vars ]
      assert_equal [ false, :env, "CODER_REAP_ENABLED" ], [ row.resolution.value, row.resolution.source, row.resolution.env_var ]
    end
  end
end
