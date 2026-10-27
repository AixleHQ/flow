# frozen_string_literal: true

require "test_helper"

# The admin writes, against real rows, the shipped flags and a live cache
# (the test env's is a null store), so a test can see the cached values dropped.
class FeatureFlags::AdminTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    @cache.write(FeatureFlags::CACHE_KEY, {})
    @admin = create(:user, :super_admin)
    @company = create(:company)
  end

  def admin = FeatureFlags::Admin

  def flag(key) = FeatureFlag.find_by(key: key.to_s)

  def cached? = @cache.exist?(FeatureFlags::CACHE_KEY)

  test "setting the global value writes the row and one audit, then drops the cached values" do
    audit = admin.set_global(:coder_reap, false, actor: @admin, reason: "  reaper deleting live boxes ")

    row = flag(:coder_reap)
    assert_equal false, row.enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal @admin, row.updated_by
    assert_equal 1, Audit.where(auditable: row).count
    audit.reload
    assert_equal [ row, nil, @admin, "feature_flag.global_set", { "enabled" => [ nil, false ] }, "reaper deleting live boxes" ],
                 [ audit.auditable, audit.associated, audit.user, audit.action, audit.audited_changes, audit.comment ]
    assert_not cached?
  end

  test "inside a caller's transaction the cache is dropped on its commit, and kept on rollback" do
    FeatureFlag.transaction do
      admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
      assert cached?, "dropped before the change was committed"
    end
    assert_not cached?

    @cache.write(FeatureFlags::CACHE_KEY, {})
    FeatureFlag.transaction do
      admin.set_global(:coder_reap, true, actor: @admin, reason: "resumed")
      raise ActiveRecord::Rollback
    end
    assert cached?
    assert_equal false, flag(:coder_reap).enabled # rubocop:disable Minitest/RefuteFalse
  end

  test "clearing the global value goes back to the declared default" do
    admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
    audit = admin.clear_global(:coder_reap, actor: @admin, reason: "use the default again")

    assert_nil flag(:coder_reap).enabled
    assert_equal "feature_flag.global_cleared", audit.action
    assert_equal({ "enabled" => [ false, nil ] }, audit.reload.audited_changes)
    assert_not cached?
  end

  test "an override records the company, and changing it records the old value" do
    first = admin.set_override(:external_runners, @company, true, actor: @admin, reason: "pilot customer")
    second = admin.set_override(:external_runners, @company, false, actor: @admin, reason: "pilot paused")

    override = flag(:external_runners).overrides.sole
    assert_equal [ false, "pilot paused", @admin ], [ override.enabled, override.reason, override.created_by ]
    assert_equal [ "feature_flag.override_set" ] * 2, [ first.action, second.action ]
    assert_equal [ @company, @company ], [ first.associated, second.associated ]
    assert_equal [ { "enabled" => [ nil, true ] }, { "enabled" => [ true, false ] } ],
                 [ first.reload.audited_changes, second.reload.audited_changes ]
  end

  test "removing an override deletes it and records its value" do
    admin.set_override(:external_runners, @company, true, actor: @admin, reason: "pilot")

    audit = admin.remove_override(:external_runners, @company, actor: @admin, reason: "pilot over")

    assert_empty flag(:external_runners).overrides
    assert_equal [ "feature_flag.override_removed", @company, { "enabled" => [ true, nil ] } ],
                 [ audit.action, audit.associated, audit.reload.audited_changes ]
  end

  test "removing an override that does not exist writes nothing" do
    assert_no_difference -> { Audit.count } do
      assert_raises(FeatureFlags::WriteRefused) do
        admin.remove_override(:external_runners, @company, actor: @admin, reason: "cleanup")
      end
    end
    assert_nil flag(:external_runners)
    assert cached?
  end

  test "turning off everywhere sets global off and deletes every override, keeping them in the audit" do
    other = create(:company)
    admin.set_global(:external_runners, true, actor: @admin, reason: "rolled out")
    admin.set_override(:external_runners, @company, true, actor: @admin, reason: "pilot")
    admin.set_override(:external_runners, other, false, actor: @admin, reason: "held back")

    audit = admin.turn_off_everywhere(:external_runners, actor: @admin, reason: "summaries leak drafts")

    row = flag(:external_runners)
    assert_equal false, row.enabled # rubocop:disable Minitest/RefuteFalse
    assert_empty row.overrides
    changes = audit.reload.audited_changes
    assert_equal "feature_flag.turned_off_everywhere", audit.action
    assert_equal [ true, false ], changes["enabled"]
    assert_equal [ [ @company.id, true, "pilot" ], [ other.id, false, "held back" ] ].sort,
                 changes["overrides"].map { |o| [ o["company_id"], o["enabled"], o["reason"] ] }.sort
  end

  test "every write requires a reason" do
    writes = [
      ->(reason) { admin.set_global(:coder_reap, true, actor: @admin, reason: reason) },
      ->(reason) { admin.clear_global(:coder_reap, actor: @admin, reason: reason) },
      ->(reason) { admin.set_override(:external_runners, @company, true, actor: @admin, reason: reason) },
      ->(reason) { admin.remove_override(:external_runners, @company, actor: @admin, reason: reason) },
      ->(reason) { admin.turn_off_everywhere(:external_runners, actor: @admin, reason: reason) }
    ]

    writes.product([ nil, "", "   " ]).each do |write, reason|
      error = assert_raises(FeatureFlags::WriteRefused) { write.call(reason) }
      assert_equal "A reason is required", error.message
    end
    assert_equal [ 0, 0, 0 ], [ FeatureFlag.count, FeatureFlagOverride.count, Audit.count ]
    assert cached?
  end

  test "an ENV-locked flag refuses every write" do
    stub_feature_env(:external_runners, "off") do
      [ -> { admin.set_global(:external_runners, true, actor: @admin, reason: "x") },
        -> { admin.clear_global(:external_runners, actor: @admin, reason: "x") },
        -> { admin.set_override(:external_runners, @company, true, actor: @admin, reason: "x") },
        -> { admin.turn_off_everywhere(:external_runners, actor: @admin, reason: "x") } ].each do |write|
        error = assert_raises(FeatureFlags::EnvLocked) { write.call }
        assert_equal "FEATURE_EXTERNAL_RUNNERS", error.variable
      end
    end
    assert_equal [ 0, 0 ], [ FeatureFlag.count, Audit.count ]
    assert cached?
  end

  test "a global flag has no company overrides" do
    error = assert_raises(FeatureFlags::WriteRefused) do
      admin.set_override(:coder_reap, @company, false, actor: @admin, reason: "x")
    end

    assert_match(/global/, error.message)
    assert_equal [ 0, 0 ], [ FeatureFlag.count, Audit.count ]
  end

  test "an undeclared key is refused" do
    assert_raises(FeatureFlags::WriteRefused) { admin.set_global(:external_runner, true, actor: @admin, reason: "x") }

    assert_equal 0, FeatureFlag.count
  end

  test "a write that fails inside its transaction leaves no rows, no audit and the cache in place" do
    # A company deleted after the page that offered it was rendered: the
    # override's foreign key fails after the flag row was written.
    gone = Company.instantiate("id" => Company.maximum(:id).to_i + 1, "name" => "Gone")

    assert_raises(ActiveRecord::InvalidForeignKey) do
      admin.set_override(:external_runners, gone, true, actor: @admin, reason: "pilot")
    end

    assert_equal [ 0, 0, 0 ], [ FeatureFlag.count, FeatureFlagOverride.count, Audit.count ]
    assert cached?
  end

  test "a flag its own env: variable locks refuses writes, naming that variable" do
    stub_feature_env(:coder_reap, "false", variable: "CODER_REAP_ENABLED") do
      error = assert_raises(FeatureFlags::EnvLocked) do
        admin.set_global(:coder_reap, true, actor: @admin, reason: "x")
      end

      assert_equal "CODER_REAP_ENABLED", error.variable
      assert_match "coder_reap is locked by CODER_REAP_ENABLED", error.message
    end
    assert_equal [ 0, 0 ], [ FeatureFlag.count, Audit.count ]
  end

  test "with its env: variable empty the flag is writable" do
    stub_feature_env(:coder_reap, "", variable: "CODER_REAP_ENABLED") do
      admin.set_global(:coder_reap, false, actor: @admin, reason: "incident")
    end

    assert_equal false, flag(:coder_reap).enabled # rubocop:disable Minitest/RefuteFalse
  end
end
