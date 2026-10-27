# frozen_string_literal: true

require "test_helper"

class RunnerStateMachineTest < ActiveSupport::TestCase
  ALL_STATES = %w[pending connected degraded unreachable disabled revoked].freeze

  # The states each event may leave from (DESIGN.md §2.5).
  ALLOWED_FROM = {
    mark_connected: %w[pending degraded unreachable],
    mark_degraded: %w[pending connected unreachable],
    mark_unreachable: %w[pending connected degraded],
    disable: %w[pending connected degraded unreachable],
    enable: %w[disabled],
    revoke: %w[pending connected degraded unreachable disabled]
  }.freeze

  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  def runner_in(status, **attributes)
    create(:runner, company: @company, created_by: @user, status: status, **attributes)
  end

  test "a new runner is pending" do
    assert_equal "pending", create(:runner, company: @company, created_by: @user).status
  end

  test "each event is allowed from exactly its states" do
    ALLOWED_FROM.each do |event, allowed|
      ALL_STATES.each do |status|
        may = runner_in(status).public_send(:"may_#{event}?")
        assert_equal allowed.include?(status), may, "#{event} from #{status}"
      end
    end
  end

  test "a refused transition raises and leaves the runner as it was" do
    runner = runner_in("revoked")

    assert_raises(AASM::InvalidTransition) { runner.enable! }
    assert_equal "revoked", runner.reload.status
  end

  # == health results ==

  test "a degraded or unreachable result stores its reason" do
    runner = runner_in("pending")

    runner.mark_unreachable!("Coder did not answer")
    assert_equal [ "unreachable", "Coder did not answer" ], runner.reload.values_at(:status, :status_reason)

    runner.mark_degraded!("Template parameter region is invalid")
    assert_equal [ "degraded", "Template parameter region is invalid" ], runner.reload.values_at(:status, :status_reason)
  end

  test "reaching connected clears the reason" do
    runner = runner_in("degraded", status_reason: "Controller below the recommended version")

    runner.mark_connected!

    assert_equal [ "connected", nil ], runner.reload.values_at(:status, :status_reason)
  end

  # == disable and enable ==

  test "disable records when, and enable returns to pending and clears it" do
    runner = runner_in("connected")

    runner.disable!
    assert_equal "disabled", runner.reload.status
    assert_not_nil runner.disabled_at

    runner.enable!
    assert_equal [ "pending", nil ], runner.reload.values_at(:status, :disabled_at)
  end

  # == revoke and delete ==

  test "revoke records when" do
    runner = runner_in("disabled")

    runner.revoke!

    assert_equal "revoked", runner.reload.status
    assert_not_nil runner.revoked_at
  end

  test "a soft delete revokes in the same write" do
    runner = runner_in("connected")

    runner.soft_delete!

    runner.reload
    assert_equal "revoked", runner.status
    assert_not_nil runner.revoked_at
    assert_not_nil runner.deleted_at
  end

  test "deleting a revoked runner keeps when it was revoked" do
    revoked_at = 2.days.ago.change(usec: 0)
    runner = runner_in("revoked", revoked_at: revoked_at)

    runner.soft_delete!

    assert_equal [ "revoked", revoked_at ], runner.reload.values_at(:status, :revoked_at)
    assert_not_nil runner.deleted_at
  end
end
