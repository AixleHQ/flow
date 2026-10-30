# frozen_string_literal: true

require "test_helper"

# Runners::Operations (docs/design/agent-runtimes/DESIGN.md §2.3, §6.1, §6.4):
# the enqueue, its wake-up and op results. The long-poll is exercised through
# the gateway in test/integration/runner_gateway_operations_test.rb.
class Runners::OperationsTest < ActiveSupport::TestCase
  setup do
    @environment = create(:runner_environment)
    @pubsub = ActionCable.server.pubsub
    @pubsub.clear_messages(channel(@environment))
  end

  test "an op is pending with its environment's next sequence, and the sequence is per environment" do
    other = create(:runner_environment, runner: @environment.runner)

    first = enqueue
    second = enqueue
    elsewhere = enqueue(other)

    assert_equal [ 1, 2, 1 ], [ first, second, elsewhere ].map(&:sequence)
    assert [ first, second, elsewhere ].all?(&:pending?)
    assert_equal [ @environment.runner_id, @environment.company_id ], [ first.runner_id, first.company_id ]
  end

  test "an enqueue wakes the environment's polls once its transaction commits" do
    RunnerOperation.transaction do
      enqueue
      assert_empty @pubsub.broadcasts(channel(@environment)), "nothing is published before the commit"
    end

    assert_equal [ "1" ], @pubsub.broadcasts(channel(@environment))
  end

  test "a rolled-back enqueue wakes nothing" do
    RunnerOperation.transaction do
      enqueue
      raise ActiveRecord::Rollback
    end

    assert_empty @pubsub.broadcasts(channel(@environment))
    assert_equal 0, RunnerOperation.count
  end

  test "the sequence stays unique within an environment" do
    enqueue

    duplicate = RunnerOperation.new(runner_environment: @environment, sequence: 1, op: "exec", state: :pending,
                                    deadline_at: 1.minute.from_now)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  test "a payload that is not an object is refused" do
    assert_raises(ArgumentError) do
      Runners::Operations.enqueue!(@environment, op: "exec", payload: "rm -rf /", deadline_at: 1.minute.from_now)
    end
  end

  test "each result status maps to its state, and the first result wins" do
    { "ok" => "completed", "error" => "failed", "expired" => "expired" }.each do |status, state|
      operation = enqueue

      Runners::Operations.record_result!(operation, status: status, result: { "exit_code" => 0 })

      operation.reload
      assert_equal state, operation.state
      assert_equal({ "exit_code" => 0 }, operation.result)
      assert_nil operation.encrypted_payload

      Runners::Operations.record_result!(operation, status: "ok", result: { "exit_code" => 1 })
      assert_equal [ state, { "exit_code" => 0 } ], [ operation.reload.state, operation.result ]
    end
  end

  private

  def enqueue(environment = @environment)
    Runners::Operations.enqueue!(environment, op: "exec", payload: { "cmd" => [ "true" ] }, deadline_at: 1.minute.from_now)
  end

  def channel(environment)
    Runners::Operations.channel_for(environment.id)
  end
end
