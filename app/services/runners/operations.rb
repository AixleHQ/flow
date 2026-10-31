# frozen_string_literal: true

module Runners
  # The queue between the platform and an environment's runner
  # (docs/design/agent-runtimes/DESIGN.md §2.3, §6.1, §6.4):
  #
  #   Runners::Operations.enqueue!(environment, op: "exec", payload: {...}, deadline_at: 5.minutes.from_now)
  #   ops = Runners::Operations.poll(environment, after: 41, wait: 25)   # GET /runner/v1/ops
  #   Runners::Operations.record_result!(operation, status: "ok", result: {...})
  #
  # An enqueue wakes the environment's waiting polls through Action Cable's
  # pub/sub (Redis, config/cable.yml) on `runner_env_<id>`, once its transaction
  # has committed. A poll subscribes there before it reads the queue, so an op
  # enqueued while the poll starts is never missed, and it returns its Active
  # Record connection to the pool while it waits, so the gateway's threads, not
  # its pool, bound how many machines can wait at once.
  module Operations
    MAX_WAIT = 25
    BATCH_SIZE = 20
    # How long a poll waits for Redis to confirm its subscription before it
    # reads anyway. Without that confirmation, an op enqueued in the gap is
    # still delivered, at the latest when the wait ends.
    SUBSCRIBE_TIMEOUT = 2

    RESULT_STATES = { "ok" => "completed", "error" => "failed", "expired" => "expired" }.freeze

    module_function

    # Puts a `pending` op with the environment's next sequence on its queue.
    # The producer is ContainerRuntime::RunnerRuntime (§15 task 8); until then
    # tests and local development call this.
    def enqueue!(environment, op:, payload:, deadline_at:)
      raise ArgumentError, "payload must be a Hash" unless payload.is_a?(Hash)

      RunnerOperation.transaction do
        # Serializes the enqueues of one environment, so the next sequence is
        # taken by one of them at a time.
        environment.lock!
        sequence = RunnerOperation.where(runner_environment_id: environment.id).maximum(:sequence).to_i + 1
        operation = RunnerOperation.create!(runner_environment: environment, sequence: sequence, op: op,
                                            payload: payload, deadline_at: deadline_at, state: :pending)
        ActiveRecord.after_all_transactions_commit { wake(environment.id, sequence) }
        operation
      end
    end

    # The environment's ops with `sequence > after`, oldest first, at most
    # BATCH_SIZE of them; the pending ones become `delivered`. With nothing to
    # return it waits up to `wait` seconds for an enqueue, and answers an empty
    # list when the wait ends. Must not be called inside a transaction: the
    # connection goes back to the pool while it waits.
    def poll(environment, after:, wait:)
      wait = wait.clamp(0, MAX_WAIT)
      return deliver!(environment.id, after: after) unless wait.positive?

      deadline = monotonic_now + wait
      channel = channel_for(environment.id)
      wakeups = Thread::Queue.new
      on_message = ->(_sequence) { wakeups << true }
      confirmed = Thread::Queue.new
      release_connection
      pubsub.subscribe(channel, on_message, -> { confirmed << true })
      confirmed.pop(timeout: SUBSCRIBE_TIMEOUT)
      instrument("subscribed", environment.id)

      loop do
        operations = deliver!(environment.id, after: after)
        remaining = deadline - monotonic_now
        return operations if operations.any? || !remaining.positive?

        release_connection
        instrument("wait", environment.id) { wakeups.pop(timeout: remaining) }
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

    def channel_for(environment_id)
      "runner_env_#{environment_id}"
    end

    def pubsub
      ActionCable.server.pubsub
    end

    def release_connection
      ActiveRecord::Base.connection_pool.release_connection
    end

    def instrument(event, environment_id, &)
      ActiveSupport::Notifications.instrument("#{event}.runner_operations", environment_id: environment_id, &)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
