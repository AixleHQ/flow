# frozen_string_literal: true

require "test_helper"

class Activities::Gates::ReconcileCiActivityTest < ActiveSupport::TestCase
  test "returns the sweep counts" do
    counts = { checked: 3, resolved: 1, stale: 1, waiting: 1, skipped: 0, errors: 0, elapsed: 0.4 }
    GateReconciler.expects(:reconcile_all).returns(counts)

    assert_equal counts, run_activity(Activities::Gates::ReconcileCiActivity)
  end

  test "no-ops when no CI gate is due for reconciliation" do
    result = run_activity(Activities::Gates::ReconcileCiActivity)

    assert_equal 0, result[:checked]
    assert_equal 0, result[:stale]
  end
end
