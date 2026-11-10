# frozen_string_literal: true

module Runners
  # The queue between the platform and an environment's runner
  # (docs/design/agent-runtimes/DESIGN.md §2.3, §6.1, §6.4):
  #
  #   Runners::Operations.enqueue!(environment, op: "exec", payload: {...}, deadline_at: 5.minutes.from_now, session:)  # nil unless session holds it
  #   ops = Runners::Operations.poll(environment, after: 41, wait: 25)   # GET /runner/v1/ops
  #   Runners::Operations.record_result!(operation, { "status" => "ok", "exit_code" => 0 })
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
  #
  # The channel carries JSON messages told apart by their `type`:
  #
  #   {"type":"op_enqueued","sequence":42}      an enqueue's wake-up (#wake)
  #   {"type":"poll_waiting","poll_id":"<uuid>"} a waiting poll's announcement (#announce)
  module Operations
    MAX_WAIT = 25
    BATCH_SIZE = 20
    # How long a poll waits for Redis to confirm its subscription before it
    # reads anyway. Without that confirmation, an op enqueued in the gap is
    # still delivered, at the latest when the wait ends.
    SUBSCRIBE_TIMEOUT = 2
    # The `type` of each message on the channel.
    WAKE_UP = "op_enqueued"
    ANNOUNCEMENT = "poll_waiting"

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

    # Puts a `pending` op with the environment's next sequence on its queue,
    # for `session`, and answers it, or nil when the session no longer holds
    # the environment (runner_environments.current_session_id): then nothing
    # is created. The hold is checked under the environment's row lock, which
    # Runners::Machines takes too, so an op read for a session that has since
    # released the machine never reaches the next session's machine, an
    # environment op (`env.reset`) included.
    #
    # A session op carries its session in the envelope as `session_id`; an
    # environment op carries none on the wire (RunnerOperation). The producer
    # is ContainerRuntime::RunnerRuntime.
    #
    # The next sequence is the environment's own counter
    # (runner_environments.op_sequence), so the prune and a session's deletion
    # can remove any finished op.
    def enqueue!(environment, op:, payload:, deadline_at:, session:)
      raise ArgumentError, "payload must be a Hash" unless payload.is_a?(Hash)
      raise ArgumentError, "session is required" if session.nil?

      RunnerOperation.transaction do
        # Serializes the enqueues of one environment, and reads its holder and
        # its counter fresh.
        environment.lock!
        next nil unless environment.current_session_id == session.id

        sequence = environment.op_sequence + 1
        environment.update_columns(op_sequence: sequence)
        operation = RunnerOperation.create!(runner_environment: environment,
                                            terminal_session: (session unless RunnerOperation::ENVIRONMENT_OPS.include?(op)),
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

    # Deletes finished ops older than RETENTION. The sequence lives on the
    # environment's counter (#enqueue!), so no row has to stay for it.
    def prune!(now: Time.current)
      scope = RunnerOperation.where(state: RunnerOperation::FINISHED_STATES).where(completed_at: ...(now - RETENTION))
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
      poll_id = SecureRandom.uuid
      messages = Thread::Queue.new
      on_message = lambda do |raw|
        message = decode(raw) || {}
        messages << message unless own_announcement?(message, poll_id)
      end
      confirmed = Thread::Queue.new
      release_connection
      pubsub.subscribe(channel, on_message, -> { confirmed << true })
      confirmed.pop(timeout: SUBSCRIBE_TIMEOUT)
      instrument("subscribed", environment.id)
      announce(channel, poll_id)

      loop do
        operations = deliver!(environment.id, after: after)
        remaining = deadline - monotonic_now
        return operations if operations.any? || !remaining.positive?

        release_connection
        message = instrument("wait", environment.id) { messages.pop(timeout: remaining) }
        if message && message["type"] == ANNOUNCEMENT
          instrument("replaced", environment.id)
          return []
        end
      end
    ensure
      pubsub.unsubscribe(channel, on_message) if on_message
    end

    # The runner's outcome of an op: `body` is the request body of
    # `POST /runner/v1/ops/:id/result`, {status: ok|error|expired, exit_code?,
    # stdout?, stderr?, data?, error?: {class, message}}, checked here against
    # runner/protocol/schemas/v1/op_result.request.json. A body that fails it
    # raises Credentials::Refused `invalid_result` and changes nothing.
    #
    # The first result wins: an op that is already completed, failed or
    # expired is returned unchanged. The same update stores the result
    # (#outcome), encrypted like the payload, and nulls the payload (§2.3).
    def record_result!(operation, body)
      body = body.to_h.deep_stringify_keys
      unless ProtocolSchema.valid?("op_result.request", body)
        raise Credentials::Refused.new("invalid_result",
                                       "`status` must be ok, error or expired, `exit_code` an integer, `stdout` and " \
                                       "`stderr` strings, `data` an object and `error` an object of `class` and " \
                                       "`message` strings.")
      end

      state = RESULT_STATES.fetch(body["status"])
      result = outcome(body)
      RunnerOperation.transaction do
        operation.lock!
        if operation.deliverable?
          operation.payload = nil
          operation.update!(state: state, result: result, completed_at: Time.current)
        end
      end
      operation
    end

    # What `result` stores: the body's known fields, a `null` one left out.
    # JSON Schema counts 1.0 as an integer, so `exit_code` is stored as one.
    def outcome(body)
      result = body.slice("exit_code", "stdout", "stderr", "data", "error").compact
      result["exit_code"] = result["exit_code"].to_i if result.key?("exit_code")
      result
    end
    # record_result! is the only way to build a stored result.
    private_class_method :outcome

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
      pubsub.broadcast(channel_for(environment_id), { type: WAKE_UP, sequence: sequence }.to_json)
    rescue StandardError => e
      # The op is committed: a poll that missed this wake-up still takes it at
      # its next read, at the latest when its wait ends.
      Rails.logger.warn("[Runners::Operations] wake-up of runner_env_#{environment_id} failed: #{e.class}: #{e.message}")
    end

    # Ends the environment's older waiting poll, which hears this on its
    # subscription. Sent once subscribed, so of two polls that start together
    # at least the later one's announcement reaches the earlier one: at most
    # one of them keeps waiting, and both may answer empty.
    def announce(channel, poll_id)
      pubsub.broadcast(channel, { type: ANNOUNCEMENT, poll_id: poll_id }.to_json)
    rescue StandardError => e
      # The older poll then waits out its own `wait`, as before this rule.
      Rails.logger.warn("[Runners::Operations] announcing a poll on #{channel} failed: #{e.class}: #{e.message}")
    end

    # A message heard on the channel as a Hash, or nil for one that is not a
    # JSON object. Any message other than another poll's announcement makes
    # the waiting poll read the queue again, so an unreadable one costs a read
    # and loses nothing.
    def decode(raw)
      message = JSON.parse(raw.to_s)
      message if message.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def own_announcement?(message, poll_id)
      message["type"] == ANNOUNCEMENT && message["poll_id"] == poll_id
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
