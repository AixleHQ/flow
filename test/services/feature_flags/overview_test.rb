# frozen_string_literal: true

require "test_helper"

# Built with its own registry and ENV layer. Rows can only be written for keys
# config/feature_flags.yml declares, so this registry declares the same keys.
class FeatureFlags::OverviewTest < ActiveSupport::TestCase
  REGISTRY = FeatureFlags::Registry.new(
    { "external_runners" => { "description" => "Runners.", "owner" => "@AixleHQ/platform", "kind" => "release",
                              "scope" => "company", "default" => false, "remove_by" => Date.new(2027, 1, 31) },
      "coder_reap" => { "description" => "Reaper.", "owner" => "@AixleHQ/platform", "kind" => "ops", "scope" => "global",
                        "default" => true, "env" => "CODER_REAP_ENABLED" } },
    source: "test registry"
  )

  setup { @company = create(:company) }

  def overview(env: {}, registry: REGISTRY)
    FeatureFlags::Overview.new(registry: registry, env: FeatureFlags::EnvSource.new(env, registry: registry))
  end

  def rows(**) = overview(**).rows.index_by { |row| row.definition.key }

  test "with no flags declared there is nothing to list" do
    assert_empty overview(registry: FeatureFlags::Registry.new({})).rows
  end

  test "a flag with no rows resolves to its declared default" do
    rows = rows()

    assert_equal %i[coder_reap external_runners], rows.keys
    assert_equal [ false, :default, nil, 0, 0 ],
                 rows[:external_runners].then { |row| [ row.resolution.value, row.resolution.source, row.global, row.overrides_on, row.overrides_off ] }
    assert_equal [ true, :default ], [ rows[:coder_reap].resolution.value, rows[:coder_reap].resolution.source ]
  end

  # Read from the rows as committed, not the cached values.
  test "values, ENV locks and override counts come from the committed rows" do
    flag = FeatureFlag.create!(key: "external_runners", enabled: true)
    flag.overrides.create!(company: @company, enabled: false, reason: "held back")
    flag.overrides.create!(company: create(:company), enabled: true, reason: "pilot")
    stale = ActiveSupport::Cache::MemoryStore.new.tap { |cache| cache.write(FeatureFlags::CACHE_KEY, {}) }
    Rails.stubs(:cache).returns(stale)

    rows = rows(env: { "FEATURE_CODER_REAP" => "off" })

    assert_equal [ true, :global, 1, 1 ],
                 rows[:external_runners].then { |row| [ row.resolution.value, row.resolution.source, row.overrides_on, row.overrides_off ] }
    assert rows[:coder_reap].locked?
    assert_equal [ false, :env ], [ rows[:coder_reap].resolution.value, rows[:coder_reap].resolution.source ]
  end

  test "a release flag past its remove-by date is flagged; an ops flag never is" do
    row = overview.row(:external_runners)

    assert_not row.past_remove_by?(Date.new(2027, 1, 31))
    assert row.past_remove_by?(Date.new(2027, 2, 1))
    assert_not overview.row(:coder_reap).past_remove_by?(Date.new(2099, 1, 1))
  end

  test "a row names the variable that locks it, or every variable that could" do
    row = overview.row(:coder_reap)
    assert_nil row.env_variable
    assert_equal %w[FEATURE_CODER_REAP CODER_REAP_ENABLED], row.env_vars

    row = overview(env: { "CODER_REAP_ENABLED" => "false" }).row(:coder_reap)
    assert row.locked?
    assert_equal [ "CODER_REAP_ENABLED", %w[CODER_REAP_ENABLED] ], [ row.env_variable, row.env_vars ]
    assert_equal [ false, :env, "CODER_REAP_ENABLED" ], [ row.resolution.value, row.resolution.source, row.resolution.env_var ]
  end
end
