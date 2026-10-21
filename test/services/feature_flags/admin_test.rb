# frozen_string_literal: true

require "test_helper"

# The admin writes, against real rows and the in-memory version token.
class FeatureFlags::AdminTest < ActiveSupport::TestCase
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  setup do
    @token = FakeFeatureFlagVersionToken.new
    @token_before_test = FeatureFlags.version_token
    FeatureFlags.version_token = @token
    @admin = create(:user, :super_admin)
    @company = create(:company)
  end

  teardown { FeatureFlags.version_token = @token_before_test }

  def admin = FeatureFlags::Admin

  def flag(key) = FeatureFlag.find_by(key: key.to_s)

  test "setting the global value writes the row and one audit, then bumps the token" do
    audit = admin.set_global(:coder_reap, false, actor: @admin, reason: "  reaper deleting live boxes ")

    row = flag(:coder_reap)
    assert_equal false, row.enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal @admin, row.updated_by
    assert_equal 1, Audit.where(auditable: row).count
    audit.reload
    assert_equal [ row, nil, @admin, "feature_flag.global_set", { "enabled" => [ nil, false ] }, "reaper deleting live boxes" ],
                 [ audit.auditable, audit.associated, audit.user, audit.action, audit.audited_changes, audit.comment ]
    assert_equal 1, @token.bumps
  end

  test "the token is bumped after the write commits, never inside its transaction" do
    open_at_call = FeatureFlag.connection.open_transactions
    open_at_bump = nil
    @token.on_bump = -> { open_at_bump = FeatureFlag.connection.open_transactions }

    admin.set_global(:coder_reap, true, actor: @admin, reason: "back on")

    assert_equal open_at_call, open_at_bump
  end

  test "inside a caller's transaction the bump waits for its commit, and is dropped on rollback" do
    FeatureFlag.transaction do
      admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
      assert_equal 0, @token.bumps
    end
    assert_equal 1, @token.bumps

    FeatureFlag.transaction do
      admin.set_global(:coder_reap, true, actor: @admin, reason: "resumed")
      raise ActiveRecord::Rollback
    end
    assert_equal 1, @token.bumps
    assert_equal false, flag(:coder_reap).enabled # rubocop:disable Minitest/RefuteFalse
  end

  test "clearing the global value goes back to the declared default" do
    admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")
    audit = admin.clear_global(:coder_reap, actor: @admin, reason: "use the default again")

    assert_nil flag(:coder_reap).enabled
    assert_equal "feature_flag.global_cleared", audit.action
    assert_equal({ "enabled" => [ false, nil ] }, audit.reload.audited_changes)
    assert_equal 2, @token.bumps
  end

  test "an override records the company, and changing it records the old value" do
    first = admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: "pilot customer")
    second = admin.set_override(:board_ai_summary, @company, false, actor: @admin, reason: "pilot paused")

    override = flag(:board_ai_summary).overrides.sole
    assert_equal [ false, "pilot paused", @admin ], [ override.enabled, override.reason, override.created_by ]
    assert_equal [ "feature_flag.override_set" ] * 2, [ first.action, second.action ]
    assert_equal [ @company, @company ], [ first.associated, second.associated ]
    assert_equal [ { "enabled" => [ nil, true ] }, { "enabled" => [ true, false ] } ],
                 [ first.reload.audited_changes, second.reload.audited_changes ]
  end

  test "removing an override deletes it and records its value" do
    admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: "pilot")

    audit = admin.remove_override(:board_ai_summary, @company, actor: @admin, reason: "pilot over")

    assert_empty flag(:board_ai_summary).overrides
    assert_equal [ "feature_flag.override_removed", @company, { "enabled" => [ true, nil ] } ],
                 [ audit.action, audit.associated, audit.reload.audited_changes ]
  end

  test "removing an override that does not exist writes nothing" do
    assert_no_difference -> { Audit.count } do
      assert_raises(FeatureFlags::WriteRefused) do
        admin.remove_override(:board_ai_summary, @company, actor: @admin, reason: "cleanup")
      end
    end
    assert_nil flag(:board_ai_summary)
    assert_equal 0, @token.bumps
  end

  test "turning off everywhere sets global off and deletes every override, keeping them in the audit" do
    other = create(:company)
    admin.set_global(:board_ai_summary, true, actor: @admin, reason: "rolled out")
    admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: "pilot")
    admin.set_override(:board_ai_summary, other, false, actor: @admin, reason: "held back")

    audit = admin.turn_off_everywhere(:board_ai_summary, actor: @admin, reason: "summaries leak drafts")

    row = flag(:board_ai_summary)
    assert_equal false, row.enabled # rubocop:disable Minitest/RefuteFalse
    assert_empty row.overrides
    changes = audit.reload.audited_changes
    assert_equal "feature_flag.turned_off_everywhere", audit.action
    assert_equal [ true, false ], changes["enabled"]
    assert_equal [ [ @company.id, true, "pilot" ], [ other.id, false, "held back" ] ].sort,
                 changes["overrides"].map { |o| [ o["company_id"], o["enabled"], o["reason"] ] }.sort
    assert_equal 4, @token.bumps
  end

  test "every write requires a reason" do
    writes = [
      ->(reason) { admin.set_global(:coder_reap, true, actor: @admin, reason: reason) },
      ->(reason) { admin.clear_global(:coder_reap, actor: @admin, reason: reason) },
      ->(reason) { admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: reason) },
      ->(reason) { admin.remove_override(:board_ai_summary, @company, actor: @admin, reason: reason) },
      ->(reason) { admin.turn_off_everywhere(:board_ai_summary, actor: @admin, reason: reason) }
    ]

    writes.product([ nil, "", "   " ]).each do |write, reason|
      error = assert_raises(FeatureFlags::WriteRefused) { write.call(reason) }
      assert_equal "A reason is required", error.message
    end
    assert_equal [ 0, 0, 0, 0 ], [ FeatureFlag.count, FeatureFlagOverride.count, Audit.count, @token.bumps ]
  end

  test "an ENV-locked flag refuses every write" do
    stub_feature_env(:board_ai_summary, "off") do
      [ -> { admin.set_global(:board_ai_summary, true, actor: @admin, reason: "x") },
        -> { admin.clear_global(:board_ai_summary, actor: @admin, reason: "x") },
        -> { admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: "x") },
        -> { admin.turn_off_everywhere(:board_ai_summary, actor: @admin, reason: "x") } ].each do |write|
        error = assert_raises(FeatureFlags::EnvLocked) { write.call }
        assert_equal "FEATURE_BOARD_AI_SUMMARY", error.variable
      end
    end
    assert_equal [ 0, 0, 0 ], [ FeatureFlag.count, Audit.count, @token.bumps ]
  end

  test "a global flag has no company overrides" do
    error = assert_raises(FeatureFlags::WriteRefused) do
      admin.set_override(:coder_reap, @company, false, actor: @admin, reason: "x")
    end

    assert_match(/global/, error.message)
    assert_equal [ 0, 0 ], [ FeatureFlag.count, Audit.count ]
  end

  test "an undeclared key is refused" do
    assert_raises(FeatureFlags::WriteRefused) { admin.set_global(:board_ai_sumary, true, actor: @admin, reason: "x") }

    assert_equal 0, FeatureFlag.count
  end

  test "a write that fails inside its transaction leaves no rows, no audit and no bump" do
    # A company deleted after the page that offered it was rendered: the
    # override's foreign key fails after the flag row was written.
    gone = Company.instantiate("id" => Company.maximum(:id).to_i + 1, "name" => "Gone")

    assert_raises(ActiveRecord::InvalidForeignKey) do
      admin.set_override(:board_ai_summary, gone, true, actor: @admin, reason: "pilot")
    end

    assert_equal [ 0, 0, 0, 0 ], [ FeatureFlag.count, FeatureFlagOverride.count, Audit.count, @token.bumps ]
  end

  test "pruning deletes the rows of an undeclared key and records what they held" do
    admin.set_override(:board_ai_summary, @company, true, actor: @admin, reason: "pilot")
    row = flag(:board_ai_summary)

    with_feature_registry(FeatureFlags::Registry.new({})) do
      audit = admin.prune(:board_ai_summary, actor: @admin, reason: "flag removed in #600")

      assert_nil flag(:board_ai_summary)
      assert_equal 0, FeatureFlagOverride.count
      assert_equal [ "feature_flag.pruned", "FeatureFlag", row.id ], [ audit.action, audit.auditable_type, audit.auditable_id ]
      assert_equal "board_ai_summary", audit.reload.audited_changes["key"]
      assert_equal [ @company.id ], audit.audited_changes["overrides"].pluck("company_id")
    end
  end

  test "a declared flag is not pruned" do
    admin.set_global(:coder_reap, false, actor: @admin, reason: "paused")

    assert_raises(FeatureFlags::WriteRefused) { admin.prune(:coder_reap, actor: @admin, reason: "x") }
    assert flag(:coder_reap)
  end
end
