# frozen_string_literal: true

require "test_helper"

# The runner gateway's operations queue (docs/design/agent-runtimes/DESIGN.md
# §6.2, §6.4, §6.7): the GET /runner/v1/ops long-poll, woken through Action
# Cable's pub/sub, and POST /runner/v1/ops/:id/result.
class RunnerGatewayOperationsTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  REGISTRATION = { os: "linux", arch: "amd64", facts: {} }.freeze
  SECRET = "ghp_payload-secret-0123456789"

  # Calls the block when the event named by `pattern` starts, on the thread
  # that instruments it: Runners::Operations instruments `subscribed` once the
  # poll's subscription is confirmed, before its first read, and `wait` around
  # each wait for a wake-up.
  class OnStart
    def initialize(&block)
      @block = block
    end

    def start(_name, _id, payload)
      @block.call(payload)
    end

    def finish(*); end
  end

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    @pair = registered_pair
    @environment = RunnerEnvironment.sole
  end

  # == liveness (task 12c) ==

  test "registration, a poll and an op result each record the machine's heartbeat, at most every 15 seconds" do
    assert_not_nil @environment.reload.last_heartbeat_at, "register records it"
    assert_equal @environment.last_heartbeat_at, @runner.reload.last_seen_at

    travel 16.seconds
    poll(@pair, wait: 0)
    assert_response :ok
    assert_in_delta Time.current, @environment.reload.last_heartbeat_at, 1
    assert_in_delta Time.current, @runner.reload.last_seen_at, 1

    recorded = @environment.last_heartbeat_at
    travel 5.seconds
    poll(@pair, wait: 0)
    assert_equal recorded, @environment.reload.last_heartbeat_at, "a second request within 15 s writes nothing"

    travel 15.seconds
    operation = enqueue
    post_result(@pair, operation, status: "ok", exit_code: 0)
    assert_response :ok
    assert_operator @environment.reload.last_heartbeat_at, :>, recorded
  end

  test "a heartbeat records the machine's heartbeat, answers 204 with no body and has no ops" do
    travel 16.seconds

    post "/runner/v1/heartbeat", headers: headers_for(@pair["access_token"])

    assert_response :no_content
    assert_empty response.body
    assert_in_delta Time.current, @environment.reload.last_heartbeat_at, 1
    assert_in_delta Time.current, @runner.reload.last_seen_at, 1
  end

  test "a heartbeat is recorded at most every 15 seconds, and one with a refresh token records nothing" do
    travel 16.seconds
    post "/runner/v1/heartbeat", headers: headers_for(@pair["access_token"])
    recorded = @environment.reload.last_heartbeat_at

    travel 5.seconds
    post "/runner/v1/heartbeat", headers: headers_for(@pair["access_token"])
    assert_response :no_content
    assert_equal recorded, @environment.reload.last_heartbeat_at

    travel 20.seconds
    post "/runner/v1/heartbeat", headers: headers_for(@pair["refresh_token"])
    assert_response :unauthorized
    assert_equal recorded, @environment.reload.last_heartbeat_at
  end

  test "a refused request records nothing" do
    travel 1.minute
    recorded = @environment.reload.last_heartbeat_at

    get "/runner/v1/ops", params: { after: 0, wait: 0 }, headers: headers_for("not-a-token")

    assert_response :unauthorized
    assert_equal recorded, @environment.reload.last_heartbeat_at
  end

  # == GET /runner/v1/ops ==

  test "an op enqueued before the poll is returned at once and becomes delivered" do
    operation = enqueue(payload: { "cmd" => [ "true" ] })

    elapsed = timed { poll(@pair, wait: 10) }

    assert_response :ok
    assert_operator elapsed, :<, 5
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [ { "id" => operation.id, "sequence" => 1, "op" => "exec", "session_id" => operation.terminal_session_id,
                     "deadline_at" => operation.deadline_at.iso8601, "payload" => { "cmd" => [ "true" ] } } ],
                 response.parsed_body["ops"]
    operation.reload
    assert operation.delivered?
    assert_not_nil operation.delivered_at
  end

  test "an op enqueued during the wait wakes the poll before the wait ends" do
    enqueuer = nil
    on_wait = OnStart.new do
      enqueuer ||= Thread.new do
        sleep 0.3
        enqueue
      end
    end

    elapsed = ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") { timed { poll(@pair, wait: 10) } }
    enqueuer.join

    assert_response :ok
    assert_equal [ 1 ], sequences
    assert_operator elapsed, :>=, 0.3
    assert_operator elapsed, :<, 5
  end

  test "an op enqueued as the poll starts, before its read, is returned at once" do
    on_subscribed = OnStart.new { enqueue }

    elapsed = ActiveSupport::Notifications.subscribed(on_subscribed, "subscribed.runner_operations") do
      timed { poll(@pair, wait: 10) }
    end

    assert_equal [ 1 ], sequences
    assert_operator elapsed, :<, 5
  end

  # The wake-up arrives between the poll's empty read and its wait, and is not
  # lost: the poll is already subscribed, so the message waits in its queue.
  test "an op enqueued after the poll's empty read and before its wait is not missed" do
    on_wait = OnStart.new { enqueue if RunnerOperation.none? }

    elapsed = ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") { timed { poll(@pair, wait: 10) } }

    assert_equal [ 1 ], sequences
    assert_operator elapsed, :<, 5
  end

  test "a poll with nothing to return answers an empty 200 when its wait ends" do
    elapsed = timed { poll(@pair, wait: 1) }

    assert_response :ok
    assert_equal({ "ops" => [] }, response.parsed_body)
    assert_operator elapsed, :>=, 1
  end

  test "a waiting poll holds no Active Record connection" do
    held = []
    on_wait = OnStart.new { held << ActiveRecord::Base.connection_handler.connection_pool_list.any?(&:active_connection?) }

    ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") { poll(@pair, wait: 1) }

    assert_response :ok
    assert_equal [ false ], held
  end

  # == one waiting poll per environment (§6.1) ==

  test "a newer poll of the environment ends the waiting one, which answers empty at once, and the newer one gets the op" do
    older = waiting_poll(@pair)
    enqueuer = nil
    on_wait = OnStart.new do
      next if Thread.current.thread_variable_get(:background_poll)

      enqueuer ||= Thread.new do
        older.join
        enqueue
      end
    end

    started = monotonic_now
    ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") { poll(@pair, wait: 10) }
    enqueuer.join

    assert_equal [ 1 ], sequences
    status, body, finished_at = older.value
    assert_equal [ 200, { "ops" => [] } ], [ status, body ]
    assert_operator finished_at - started, :<, 2
  end

  test "a poll of another environment does not end a waiting one" do
    theirs = registered_pair(name: "build-02")
    older = waiting_poll(@pair)

    poll(theirs, wait: 1)
    assert_equal [], sequences
    enqueue

    status, body, = older.value
    assert_equal [ 200, [ 1 ] ], [ status, body["ops"].pluck("sequence") ]
  end

  test "a poll with wait=0 does not end a waiting one" do
    older = waiting_poll(@pair)

    poll(@pair, wait: 0)
    assert_equal [], sequences
    enqueue

    status, body, = older.value
    assert_equal [ 200, [ 1 ] ], [ status, body["ops"].pluck("sequence") ]
  end

  # A poll hears its own announcement on the channel too, and ignores it: a
  # lone poll still waits out its wait (above) and is woken by an enqueue.
  test "a lone poll is not ended by its own announcement" do
    replaced = []
    on_replaced = OnStart.new { |payload| replaced << payload }

    elapsed = ActiveSupport::Notifications.subscribed(on_replaced, "replaced.runner_operations") { timed { poll(@pair, wait: 1) } }

    assert_equal({ "ops" => [] }, response.parsed_body)
    assert_operator elapsed, :>=, 1
    assert_empty replaced
  end

  # The channel's messages are typed JSON: an enqueue's wake-up and a poll's
  # announcement are told apart by `type`, not by the shape of a string.
  test "a waiting poll announces itself with a typed message, and an enqueue wakes with one" do
    pubsub = ActionCable.server.pubsub
    channel = "runner_env_#{@environment.id}"
    pubsub.clear_messages(channel)

    poll(@pair, wait: 1)
    enqueue

    announcement, wake_up = pubsub.broadcasts(channel).map { |message| JSON.parse(message) }
    assert_equal "poll_waiting", announcement["type"]
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, announcement["poll_id"])
    assert_equal({ "type" => "op_enqueued", "sequence" => 1 }, wake_up)
  end

  test "a message on the channel that is not another poll's announcement does not end a waiting poll" do
    older = waiting_poll(@pair)

    [ "not json", "[1]", { type: "something_else" }.to_json ].each do |message|
      ActionCable.server.pubsub.broadcast("runner_env_#{@environment.id}", message)
    end
    enqueue

    status, body, = older.value
    assert_equal [ 200, [ 1 ] ], [ status, body["ops"].pluck("sequence") ]
  end

  test "after leaves out acknowledged ops, and ops past it are delivered again until acknowledged" do
    3.times { enqueue }

    poll(@pair, after: 1, wait: 0)
    assert_equal [ 2, 3 ], sequences
    poll(@pair, after: 1, wait: 0)
    assert_equal [ 2, 3 ], sequences
    poll(@pair, after: 3, wait: 0)
    assert_equal [], sequences
  end

  test "a poll returns at most a batch, oldest first" do
    (Runners::Operations::BATCH_SIZE + 1).times { enqueue }

    poll(@pair, wait: 0)
    assert_equal (1..Runners::Operations::BATCH_SIZE).to_a, sequences
    poll(@pair, after: Runners::Operations::BATCH_SIZE, wait: 0)
    assert_equal [ Runners::Operations::BATCH_SIZE + 1 ], sequences
  end

  test "an op that has a result is not delivered again" do
    operation = enqueue
    post_result(@pair, operation, status: "ok")

    poll(@pair, wait: 0)

    assert_equal [], sequences
  end

  test "a poll sees only its own environment's ops" do
    theirs = registered_pair(name: "build-02")
    enqueue
    enqueue(RunnerEnvironment.find_by!(display_name: "build-02"))

    poll(@pair, wait: 0)
    assert_equal [ RunnerEnvironment.find_by!(display_name: "build-01").id ],
                 RunnerOperation.where(id: response.parsed_body["ops"].pluck("id")).pluck(:runner_environment_id)
    poll(theirs, wait: 0)
    assert_equal [ 1 ], sequences
  end

  test "a malformed after or wait is refused" do
    poll(@pair, after: -1, wait: 0)
    assert_refused :bad_request, "invalid_request"
    get "/runner/v1/ops", params: { after: "1", wait: "soon" }, headers: headers_for(@pair["access_token"])
    assert_refused :bad_request, "invalid_request"
  end

  test "an after past the bigint range of sequence is refused, and the largest one is not" do
    poll(@pair, after: "9223372036854775808", wait: 0)
    assert_refused :bad_request, "invalid_request"

    poll(@pair, after: "9223372036854775807", wait: 0)
    assert_equal [], sequences
  end

  # The checks of the before_action ran before the wait: a change during it
  # must still refuse the payload a wake-up then brings.
  {
    "a credential revoked" => [ :unauthorized, "invalid_token",
                                -> { RunnerCredential.where(runner_environment: @environment).update_all(revoked_at: Time.current) } ],
    "a runner revoked" => [ :unauthorized, "invalid_token", -> { @runner.revoke! } ],
    "an environment gone" => [ :unauthorized, "invalid_token", -> { @environment.update!(state: :gone) } ],
    "the flag turned off" => [ :forbidden, "runners_disabled",
                               -> { FeatureFlag.find_by!(key: "external_runners").overrides.find_by!(company: @company).update!(enabled: false) } ]
  }.each do |change, (status, error, apply)|
    test "#{change} during the wait refuses the woken poll without the payload" do
      operation = nil
      on_wait = OnStart.new do
        next if operation

        instance_exec(&apply)
        operation = enqueue(payload: { "content" => SECRET })
      end

      ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") { poll(@pair, wait: 10) }

      assert_refused status, error
      assert_not_includes response.body, SECRET
      assert_nil response.parsed_body["ops"]
      # The poll marked the op delivered before the re-check refused, so it
      # stays `delivered` without the runner having received it (§15 task 8).
      assert_equal "delivered", operation.reload.state
      assert_equal({ "content" => SECRET }, operation.payload)
    end
  end

  # == POST /runner/v1/ops/:id/result ==

  test "each status maps to its state, and the result is stored with the payload nulled" do
    { "ok" => "completed", "error" => "failed", "expired" => "expired" }.each do |status, state|
      operation = enqueue
      poll(@pair, after: operation.sequence - 1, wait: 0)

      post_result(@pair, operation, status: status, exit_code: 0, stdout: "out", stderr: "",
                                    data: { "bytes" => 3 }, error: { "class" => "Timeout", "message" => "late" })

      assert_response :ok
      assert_equal({ "id" => operation.id, "state" => state }, response.parsed_body)
      operation.reload
      assert_equal state, operation.state
      assert_not_nil operation.completed_at
      assert_nil operation.encrypted_payload
      assert_nil operation.payload
      assert_equal({ "exit_code" => 0, "stdout" => "out", "stderr" => "", "data" => { "bytes" => 3 },
                     "error" => { "class" => "Timeout", "message" => "late" } }, operation.result)
    end
  end

  test "a repeated result answers 200 and changes nothing" do
    operation = enqueue
    post_result(@pair, operation, status: "ok", exit_code: 0)
    first = operation.reload.attributes

    post_result(@pair, operation, status: "error", exit_code: 1)

    assert_response :ok
    assert_equal({ "id" => operation.id, "state" => "completed" }, response.parsed_body)
    assert_equal first, operation.reload.attributes
  end

  test "an invalid result is refused and changes nothing" do
    operation = enqueue

    [ { status: "done" }, { status: "ok", exit_code: "0" }, { status: "ok", stdout: [ "x" ] },
      { status: "ok", data: "x" }, { status: "error", error: { "class" => 1 } }, { status: "error", error: {} },
      { status: "error", error: { "class" => "Timeout" } }, { status: "error", error: { "message" => "late" } },
      { status: "error", error: { "class" => "Timeout", "message" => "late", "detail" => "x" } } ].each do |body|
      post_result(@pair, operation, **body)
      assert_refused :unprocessable_entity, "invalid_result"
    end
    assert operation.reload.pending?
    assert_equal({ "cmd" => "true" }, operation.payload)
  end

  test "a null field of a result counts as absent, and an exit_code of 1.0 is stored as an integer" do
    operation = enqueue

    post_result(@pair, operation, status: "error", exit_code: 1.0, stdout: nil, data: nil, error: nil, extra: "ignored")

    assert_response :ok
    assert_equal({ "exit_code" => 1 }, operation.reload.result)
    assert_kind_of Integer, operation.result["exit_code"]
  end

  test "another environment's op, or an unknown one, is not found" do
    theirs = registered_pair(name: "build-02")
    operation = enqueue

    post_result(theirs, operation, status: "ok")
    assert_refused :not_found, "not_found"
    post "/runner/v1/ops/0/result", params: { status: "ok" }, headers: headers_for(@pair["access_token"]), as: :json
    assert_refused :not_found, "not_found"

    assert operation.reload.pending?
  end

  # == refusals, on both endpoints ==

  test "a bad token is refused on both endpoints" do
    operation = enqueue

    [ "aracc_not-a-token", @pair["refresh_token"] ].each do |token|
      poll({ "access_token" => token }, wait: 0)
      assert_refused :unauthorized, "invalid_token"
      post_result({ "access_token" => token }, operation, status: "ok")
      assert_refused :unauthorized, "invalid_token"
    end
    assert operation.reload.pending?
  end

  test "with the flag off both endpoints answer runners_disabled" do
    operation = enqueue

    with_feature(:external_runners, false, company: @company) do
      poll(@pair, wait: 0)
      assert_refused :forbidden, "runners_disabled"
      post_result(@pair, operation, status: "ok")
      assert_refused :forbidden, "runners_disabled"
    end
    assert operation.reload.pending?
  end

  test "a revoked runner gets 401 on both endpoints" do
    operation = enqueue
    @runner.revoke!

    poll(@pair, wait: 0)
    assert_refused :unauthorized, "invalid_token"
    post_result(@pair, operation, status: "ok")
    assert_refused :unauthorized, "invalid_token"
    assert operation.reload.pending?
  end

  test "a gone environment gets 401 on both endpoints" do
    operation = enqueue
    @environment.update!(state: :gone)

    poll(@pair, wait: 0)
    assert_refused :unauthorized, "invalid_token"
    post_result(@pair, operation, status: "ok")
    assert_refused :unauthorized, "invalid_token"
    assert operation.reload.pending?
  end

  # == secrets ==

  test "the payload and the result are encrypted at rest, and neither reaches the log" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io, level: :debug)
    Rails.logger.broadcast_to(logger)

    operation = enqueue(payload: { "path" => "/home/agent/.credentials", "content" => SECRET })
    poll(@pair, wait: 0)
    assert_equal SECRET, response.parsed_body["ops"].sole.dig("payload", "content")
    post_result(@pair, operation, status: "ok", stdout: "token=#{SECRET}", stderr: SECRET,
                                  data: { "content" => SECRET }, error: { "class" => "Leak", "message" => SECRET })
    assert_response :ok

    assert_match %r{/runner/v1/ops/#{operation.id}/result}, io.string
    assert_not_includes io.string, SECRET
    stored = RunnerOperation.connection.select_value(
      RunnerOperation.where(id: operation.id).select(:encrypted_result).to_sql
    )
    assert_not_includes stored, SECRET
    assert_equal "token=#{SECRET}", operation.reload.result["stdout"]
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  private

  # An op is for the session that holds the machine.
  def enqueue(environment = @environment, op: "exec", payload: { "cmd" => "true" })
    session = environment.reload.current_session || create(:runner_session, :holding, environment: environment)
    Runners::Operations.enqueue!(environment, op: op, payload: payload, session: session,
                                              deadline_at: 5.minutes.from_now.change(usec: 0))
  end

  def headers_for(token)
    { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1", "X-Aixle-Runner-Version" => "1.4.0" }
  end

  def poll(pair, after: 0, wait: 25)
    get "/runner/v1/ops", params: { after: after, wait: wait }, headers: headers_for(pair["access_token"])
  end

  def post_result(pair, operation, **body)
    post "/runner/v1/ops/#{operation.id}/result", params: body, headers: headers_for(pair["access_token"]), as: :json
  end

  def registered_pair(name: "build-01")
    post "/runner/v1/register", params: REGISTRATION.merge(name: name),
                                headers: headers_for(Runners::Credentials.mint_registration!(@runner)), as: :json
    assert_response :created
    response.parsed_body
  end

  def sequences
    assert_response :ok
    response.parsed_body["ops"].pluck("sequence")
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Starts a poll of `pair` on its own thread and integration session, and
  # returns that thread once the poll is waiting. Its value is the poll's
  # status, its body and when it answered (monotonic_now).
  def waiting_poll(pair, wait: 10)
    waiting = Queue.new
    on_wait = OnStart.new { waiting << true if Thread.current.thread_variable_get(:background_poll) }
    thread = Thread.new do
      Thread.current.thread_variable_set(:background_poll, true)
      session = open_session
      ActiveSupport::Notifications.subscribed(on_wait, "wait.runner_operations") do
        session.get "/runner/v1/ops", params: { after: 0, wait: wait }, headers: headers_for(pair["access_token"])
      end
      [ session.response.status, session.response.parsed_body, monotonic_now ]
    end
    waiting.pop(timeout: 5) || flunk("the background poll never waited")
    thread
  end

  def assert_refused(status, error)
    assert_response status
    assert_equal error, response.parsed_body["error"]
  end
end
