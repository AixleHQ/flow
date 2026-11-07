# frozen_string_literal: true

module Runners
  # The queue between the platform and an environment's runner
  # (docs/design/agent-runtimes/DESIGN.md §2.3, §6.1, §6.4):
  #
  #   Runners::Operations.enqueue!(environment, op: "exec", payload: {...}, deadline_at: 5.minutes.from_now, session:)
  #   ops = Runners::Operations.poll(environment, after: 41, wait: 25)   # GET /runner/v1/ops
  #   Runners::Operations.record_result!(operation, status: "ok", result: {...})
  #   Runners::Operations.await(operation)                               # ContainerRuntime::RunnerRuntime
  #   Runners::Operations.expire_overdue! / prune!                       # RunnerOperationsSweepWorkflow
  #
  # An enqueue wakes the environment's waiting polls through Action Cable's
  # pub/sub (Redis, config/cable.yml) on `runner_env_<id>`, once its transaction
  # has committed. A poll subscribes there before it reads the queue, so an op
  # enqueued while the poll starts is never missed, and it returns its Active
  # Record connection to the pool while it waits, so the gateway's threads, not
  # its pool, bound how many machines can wait at once.
  #
  # One poll of an environment waits at a time (§6.1). A poll that is going to
  # wait announces itself on the same channel once subscribed, and a waiting
  # poll of that environment that hears another poll's announcement stops
  # waiting and answers an empty list. Its ops stay deliverable until `after`
  # acknowledges them, so none is lost.
  module Operations
    MAX_WAIT = 25
    BATCH_SIZE = 20
    # How long a poll waits for Redis to confirm its subscription before it
    # reads anyway. Without that confirmation, an op enqueued in the gap is
    # still delivered, at the latest when the wait ends.
    SUBSCRIBE_TIMEOUT = 2
    # Starts a waiting poll's announcement on the channel, followed by the
    # poll's own id. An enqueue publishes a bare sequence, which never starts
    # with it.
    ANNOUNCEMENT = "poll:"

    RESULT_STATES = { "ok" => "completed", "error" => "failed", "expired" => "expired" }.freeze

    # How long past its deadline an op that nobody waits for still waits for
    # the runner's own answer before the sweep expires it (#expire_overdue!). A
    # runner that received the op in time posts its result a moment after the
    # deadline at most. The wait of #await has no grace: it ends at the deadline.
    EXPIRY_GRACE = 10.seconds
    # Finished ops older than this are pruned (DESIGN.md §2.3).
    RETENTION = 7.days
    PRUNE_BATCH = 1000

    module_function

    # Puts a `pending` op with the environment's next sequence on its queue.
    # A session op names its session, which the envelope carries as
    # `session_id`; an environment op names none (RunnerOperation). The
    # producer is ContainerRuntime::RunnerRuntime.
    #
    # The next sequence is MAX(sequence) + 1, so the prune keeps each
    # environment's newest op (see #prune!).
    def enqueue!(environment, op:, payload:, deadline_at:, session: nil)
      raise ArgumentError, "payload must be a Hash" unless payload.is_a?(Hash)

      RunnerOperation.transaction do
        # Serializes the enqueues of one environment, so the next sequence is
        # taken by one of them at a time.
        environment.lock!
        sequence = RunnerOperation.where(runner_environment_id: environment.id).maximum(:sequence).to_i + 1
        operation = RunnerOperation.create!(runner_environment: environment, terminal_session: session,
                                            sequence: sequence, op: op, payload: payload,
                                            deadline_at: deadline_at, state: :pending)
        ActiveRecord.after_all_transactions_commit { wake(environment.id, sequence) }
        instrument("enqueued", environment.id, operation: operation)
        operation
      end
    end

    # Waits for the op's result and returns the op, finished. An op still
    # without a result at its deadline is expired here, so the caller, whose
    # activity the deadline was set inside, learns the outcome before the
    # activity ends. Must not be called inside a transaction, which would hide
    # the result from it.
    #
    # `on_wait` runs between two looks, an activity's heartbeat and
    # cancellation check for one.
    #
    # Waiting by polling the database is to be revisited with P1 (DESIGN.md
    # §16), for example with a wake-up on the pub/sub the long-poll already
    # uses (#wake).
    def await(operation, poll_interval: Settings.runners.op_poll_interval.to_f, on_wait: nil)
      interval = poll_interval
      loop do
        operation = RunnerOperation.uncached { RunnerOperation.find(operation.id) }
        return operation unless operation.deliverable?

        if Time.current >= operation.deadline_at
          expire!(operation)
          return operation.reload
        end

        on_wait&.call
        sleep(interval) if interval.positive?
        interval = [ interval * 2, 1.0 ].min if interval.positive?
      end
    end

    # Expires one op that has no result, as a runner's `expired` result would:
    # the payload is nulled, and a result that arrives later changes nothing,
    # since the first outcome wins.
    def expire!(operation)
      RunnerOperation.transaction do
        operation.lock!
        if operation.deliverable?
          operation.payload = nil
          operation.update!(state: :expired, completed_at: Time.current)
        end
      end
      operation
    end

    # Expires every op past its deadline and EXPIRY_GRACE that has no result,
    # `pending` or `delivered`, the ops nobody waits for:
    # `delivered` does not prove the runner received an op (§5.4), so a runner
    # that never answers must not leave it open.
    # Rows a result holds are skipped, and the next sweep sees them settled.
    def expire_overdue!(now: Time.current)
      expired = 0
      RunnerOperation.deliverable.where(deadline_at: ...(now - EXPIRY_GRACE)).in_batches(of: PRUNE_BATCH) do |batch|
        RunnerOperation.transaction do
          ids = batch.lock("FOR UPDATE SKIP LOCKED").pluck(:id)
          expired += RunnerOperation.where(id: ids).deliverable.update_all(
            state: "expired", encrypted_payload: nil, completed_at: now, updated_at: now
          )
        end
      end
      expired
    end

    # Deletes finished ops older than RETENTION, except each environment's
    # newest op. #enqueue! takes the next sequence as MAX(sequence) + 1, so
    # pruning the newest row would hand out a sequence the runner has already
    # acknowledged, and its `after` would hide every op enqueued from then on.
    def prune!(now: Time.current)
      newest = RunnerOperation.select("DISTINCT ON (runner_environment_id) id").order(:runner_environment_id, sequence: :desc)
      scope = RunnerOperation.where(state: RunnerOperation::FINISHED_STATES)
                             .where(completed_at: ...(now - RETENTION))
                             .where.not(id: newest)
      pruned = 0
      scope.in_batches(of: PRUNE_BATCH) { |batch| pruned += batch.delete_all }
      pruned
    end

    # The environment's ops with `sequence > after`, oldest first, at most
    # BATCH_SIZE of them; the pending ones become `delivered`. With nothing to
    # return it waits up to `wait` seconds for an enqueue, and answers an empty
    # list when the wait ends, or at once when a newer poll of the environment
    # announces itself. A poll with `wait` 0 neither waits nor announces, so it
    # ends no other poll. Must not be called inside a transaction: the
    # connection goes back to the pool while it waits.
    def poll(environment, after:, wait:)
      wait = wait.clamp(0, MAX_WAIT)
      return deliver!(environment.id, after: after) unless wait.positive?

      deadline = monotonic_now + wait
      channel = channel_for(environment.id)
      announcement = "#{ANNOUNCEMENT}#{SecureRandom.uuid}"
      messages = Thread::Queue.new
      on_message = ->(message) { messages << message unless message == announcement }
      confirmed = Thread::Queue.new
      release_connection
      pubsub.subscribe(channel, on_message, -> { confirmed << true })
      confirmed.pop(timeout: SUBSCRIBE_TIMEOUT)
      instrument("subscribed", environment.id)
      announce(channel, announcement)

      loop do
        operations = deliver!(environment.id, after: after)
        remaining = deadline - monotonic_now
        return operations if operations.any? || !remaining.positive?

        release_connection
        message = instrument("wait", environment.id) { messages.pop(timeout: remaining) }
        if message&.start_with?(ANNOUNCEMENT)
          instrument("replaced", environment.id)
          return []
        end
      end
    ensure
      pubsub.unsubscribe(channel, on_message) if on_message
    end

    # The runner's outcome of an op. The first result wins: an op that is
    # already completed, failed or expired is returned unchanged. The same
    # update stores the result, encrypted like the payload, and nulls the
    # payload (§2.3).
    def record_result!(operation, status:, result:)
      state = RESULT_STATES.fetch(status)
      RunnerOperation.transaction do
        operation.lock!
        if operation.deliverable?
          operation.payload = nil
          operation.update!(state: state, result: result, completed_at: Time.current)
        end
      end
      operation
    end

    # Selects the deliverable ops and marks the pending ones `delivered` in one
    # transaction, with the rows locked FOR UPDATE, the lock record_result!
    # takes: a result that holds an op's row first is committed before this
    # read sees the row, which then no longer matches, so an op with a result
    # is never returned; a result that comes second waits for the delivery.
    def deliver!(environment_id, after:)
      RunnerOperation.transaction do
        # Uncached: the request's query cache would answer a repeated read from
        # the empty result of the one before the wait.
        operations = RunnerOperation.uncached do
          RunnerOperation.deliverable.where(runner_environment_id: environment_id).where("sequence > ?", after)
                         .order(:sequence).limit(BATCH_SIZE).lock.to_a
        end
        pending_ids = operations.select(&:pending?).map(&:id)
        if pending_ids.any?
          now = Time.current
          RunnerOperation.where(id: pending_ids).update_all(state: "delivered", delivered_at: now, updated_at: now)
        end
        operations
      end
    end

    def wake(environment_id, sequence)
      pubsub.broadcast(channel_for(environment_id), sequence.to_s)
    rescue StandardError => e
      # The op is committed: a poll that missed this wake-up still takes it at
      # its next read, at the latest when its wait ends.
      Rails.logger.warn("[Runners::Operations] wake-up of runner_env_#{environment_id} failed: #{e.class}: #{e.message}")
    end

    # Ends the environment's older waiting poll, which hears this on its
    # subscription. Sent once subscribed, so of two polls that start together
    # at least the later one's announcement reaches the earlier one: at most
    # one of them keeps waiting, and both may answer empty.
    def announce(channel, announcement)
      pubsub.broadcast(channel, announcement)
    rescue StandardError => e
      # The older poll then waits out its own `wait`, as before this rule.
      Rails.logger.warn("[Runners::Operations] announcing a poll on #{channel} failed: #{e.class}: #{e.message}")
    end

    def channel_for(environment_id)
      "runner_env_#{environment_id}"
    end

    def pubsub
      ActionCable.server.pubsub
    end

    def release_connection
      ActiveRecord::Base.connection_pool.release_connection
    end

    def instrument(event, environment_id, **payload, &)
      ActiveSupport::Notifications.instrument("#{event}.runner_operations", environment_id: environment_id, **payload, &)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
