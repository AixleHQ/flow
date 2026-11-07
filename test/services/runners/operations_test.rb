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

    duplicate = RunnerOperation.new(runner_environment: @environment, sequence: 1, op: "env.reset", state: :pending,
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

  test "a session op names its session, which runs on the op's machine; an environment op names none" do
    session = create(:runner_session, environment: @environment)

    operation = Runners::Operations.enqueue!(@environment, op: "exec", payload: { "cmd" => [ "true" ] },
                                                           deadline_at: 1.minute.from_now, session: session)

    assert_equal session, operation.terminal_session
    refusals = [
      -> { Runners::Operations.enqueue!(@environment, op: "exec", payload: {}, deadline_at: 1.minute.from_now) },
      -> { Runners::Operations.enqueue!(@environment, op: "env.reset", payload: {}, deadline_at: 1.minute.from_now, session: session) },
      lambda do
        other = create(:runner_environment, runner: @environment.runner)
        Runners::Operations.enqueue!(other, op: "exec", payload: {}, deadline_at: 1.minute.from_now, session: session)
      end
    ]
    messages = refusals.map { |refusal| assert_raises(ActiveRecord::RecordInvalid) { refusal.call }.message }

    assert_equal [
      "Validation failed: Terminal session is required for a session op",
      "Validation failed: Terminal session must be empty for an environment op",
      "Validation failed: Terminal session does not run on this environment"
    ], messages
    assert_equal 1, RunnerOperation.count
  end

  test "await returns the op once it has its result" do
    operation = enqueue
    Runners::Operations.record_result!(operation, status: "ok", result: { "data" => { "removed_volumes" => [] } })

    awaited = Runners::Operations.await(operation)

    assert_equal [ "completed", { "data" => { "removed_volumes" => [] } } ], [ awaited.state, awaited.result ]
  end

  test "await expires an op the runner did not answer at its deadline, without the sweep's grace" do
    operation = enqueue(deadline_at: 1.second.ago)
    waits = 0

    awaited = Runners::Operations.await(operation, on_wait: -> { waits += 1 })

    assert_equal 0, waits, "an op past its deadline is not waited for"
    assert awaited.expired?
    assert_nil awaited.encrypted_payload
    assert_not_nil awaited.completed_at
    Runners::Operations.record_result!(awaited, status: "ok", result: {})
    assert awaited.reload.expired?, "a late result changes nothing"
  end

  test "the sweep expires ops past their deadline, pending or delivered, and leaves the others" do
    pending = enqueue(deadline_at: 2.minutes.ago)
    delivered = enqueue(deadline_at: 2.minutes.ago)
    delivered.update!(state: :delivered, delivered_at: 3.minutes.ago)
    in_grace = enqueue(deadline_at: 5.seconds.ago)
    future = enqueue(deadline_at: 5.minutes.from_now)
    answered = enqueue(deadline_at: 2.minutes.ago)
    Runners::Operations.record_result!(answered, status: "ok", result: {})

    assert_equal 2, Runners::Operations.expire_overdue!

    assert_equal %w[expired expired pending pending completed],
                 [ pending, delivered, in_grace, future, answered ].map { |op| op.reload.state }
    assert_nil pending.encrypted_payload
    assert_nil delivered.encrypted_payload
    assert_not_nil in_grace.encrypted_payload
  end

  test "the prune deletes finished ops after seven days and keeps each environment's newest" do
    other = create(:runner_environment, runner: @environment.runner)
    old = 3.times.map { enqueue }
    open_op = enqueue
    other_op = enqueue(other)
    (old + [ other_op ]).each { |op| Runners::Operations.record_result!(op, status: "ok", result: {}) }
    young = enqueue
    Runners::Operations.record_result!(young, status: "error", result: {})
    newest = enqueue
    Runners::Operations.record_result!(newest, status: "ok", result: {})
    RunnerOperation.where(id: old + [ other_op, newest ]).update_all(completed_at: 8.days.ago)

    assert_equal 3, Runners::Operations.prune!

    assert_equal [ open_op.id, other_op.id, young.id, newest.id ].sort, RunnerOperation.pluck(:id).sort
    assert_equal newest.sequence + 1, enqueue.sequence, "the next sequence follows the newest op, which the prune kept"
  end

  private

  def enqueue(environment = @environment, deadline_at: 1.minute.from_now)
    Runners::Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: deadline_at)
  end

  def channel(environment)
    Runners::Operations.channel_for(environment.id)
  end
end
