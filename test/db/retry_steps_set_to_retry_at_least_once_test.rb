# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261110100000_retry_steps_set_to_retry_at_least_once")

class RetryStepsSetToRetryAtLeastOnceTest < ActiveSupport::TestCase
  setup { @workflow = create(:workflow) }

  def migrate
    migration = RetryStepsSetToRetryAtLeastOnce.new
    migration.suppress_messages { migration.up }
  end

  # update_columns: rows saved before Step raised the count itself.
  def saved_step(on_failure, max_retries)
    step = create(:step, workflow: @workflow, on_failure: on_failure)
    step.update_columns(max_retries: max_retries)
    step
  end

  test "a step the builder saved to retry with no retries is set to retry once" do
    step = saved_step("retry", 0)

    migrate

    assert_equal 1, step.reload.max_retries
  end

  test "a retry count outside 0 to 10 is brought inside it" do
    many = saved_step("retry", 25)
    negative = saved_step("fail", -2)

    migrate

    assert_equal [ 10, 0 ], [ many.reload.max_retries, negative.reload.max_retries ]
  end

  test "counts already in range are left alone" do
    retrying = saved_step("retry", 3)
    failing = saved_step("fail", 0)
    skipping = saved_step("skip", 2)

    migrate

    assert_equal [ 3, 0, 2 ], [ retrying, failing, skipping ].map { |s| s.reload.max_retries }
  end
end
