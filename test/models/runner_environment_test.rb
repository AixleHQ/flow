# frozen_string_literal: true

require "test_helper"

class RunnerEnvironmentTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
  end

  test "takes its runner's company" do
    environment = RunnerEnvironment.create!(runner: @runner, key: "aixle-r1-a", origin: :registered, state: :registered,
                                            display_name: "build-01")

    assert_equal @runner.company, environment.company
  end

  test "a registered machine needs a name" do
    environment = build(:runner_environment, runner: @runner, display_name: nil)

    assert_not environment.valid?
    assert environment.errors.added?(:display_name, :blank)
  end

  test "facts are an object" do
    environment = build(:runner_environment, runner: @runner, facts: [ "docker" ])

    assert_not environment.valid?
    assert_includes environment.errors[:facts], "must be an object"
  end

  test "the database ties an environment to its runner's company and a credential to its environment's runner" do
    other_company = create(:company)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      build(:runner_environment, runner: @runner, company: other_company).save!(validate: false)
    end

    other_environment = create(:runner_environment, runner: create(:runner, :manual, company: @runner.company))
    assert_raises(ActiveRecord::InvalidForeignKey) do
      RunnerCredential.new(runner: @runner, company: @runner.company, runner_environment: other_environment, kind: :access,
                           token_digest: "x", family_id: SecureRandom.uuid, expires_at: 1.hour.from_now).save!(validate: false)
    end
  end

  # The key is checked at the commit, which a transactional test never reaches,
  # so the test asks for the check at once.
  test "the database ties the session that holds a machine to the machine's company" do
    environment = create(:runner_environment, runner: @runner)
    other_session = create(:runner_session)
    assert_not_equal environment.company_id, other_session.company_id

    error = assert_raises(ActiveRecord::InvalidForeignKey) do
      RunnerEnvironment.transaction(requires_new: true) do
        environment.update_columns(current_session_id: other_session.id)
        check_session_company_key
      end
    end
    assert_match "fk_runner_environments_current_session_company", error.message
  end

  test "a deleted session stops holding its machine, which the company key lets through" do
    environment = create(:runner_environment, runner: @runner)
    session = create(:runner_session, :holding, environment: environment)

    session.destroy!

    assert_nothing_raised { check_session_company_key }
    assert_nil environment.reload.current_session_id
  end

  test "not_heard_since holds the machines never heard or last heard at or before the time" do
    now = Time.current
    never = create(:runner_environment, runner: @runner, last_heartbeat_at: nil)
    stale = create(:runner_environment, runner: @runner, last_heartbeat_at: now - 1.minute)
    at_time = create(:runner_environment, runner: @runner, last_heartbeat_at: now)
    create(:runner_environment, runner: @runner, last_heartbeat_at: now + 1.second)

    assert_equal [ never.id, stale.id, at_time.id ].sort, RunnerEnvironment.not_heard_since(now).pluck(:id).sort
  end

  test "display_state: idle without a session and online with one while heard, offline after 90 seconds or never" do
    now = Time.current
    machine = create(:runner_environment, runner: @runner, last_heartbeat_at: now - 89.seconds)
    assert_equal "idle", machine.display_state(now)

    machine.update!(current_session: create(:runner_session, environment: machine, runner_environment: nil))
    assert_equal "online", machine.display_state(now)

    machine.update!(last_heartbeat_at: now - 91.seconds)
    assert_equal "offline", machine.display_state(now)

    machine.update!(last_heartbeat_at: nil)
    assert_equal "offline", machine.display_state(now)
  end

  test "display_state: a silent machine executing a delivered op within its deadline is not offline" do
    now = Time.current
    machine = create(:runner_environment, runner: @runner, last_heartbeat_at: now - 5.minutes)
    session = create(:runner_session, :holding, environment: machine)
    operation = Runners::Operations.enqueue!(machine.reload, op: "exec", payload: { "cmd" => "true" }, session: session,
                                                             deadline_at: now + 10.minutes)

    assert_equal "offline", machine.display_state(now), "an op that was not delivered does not count"

    operation.update!(state: :delivered, delivered_at: now - 4.minutes)
    assert_equal "online", RunnerEnvironment.find(machine.id).display_state(now)
    assert_equal "offline", RunnerEnvironment.find(machine.id).display_state(now + 11.minutes), "past the deadline it is offline again"
  end

  test "display_state: failed and gone machines show as such, however recently they were heard" do
    gone = create(:runner_environment, runner: @runner, state: :gone)
    failed = create(:runner_environment, runner: @runner)
    Runners::Machines.fail!(failed, "env.reset failed")

    assert_equal "gone", gone.display_state
    assert_equal "failed", failed.reload.display_state
  end

  test "display_state over includes(:delivered_operations) makes no query per machine" do
    create_list(:runner_environment, 3, runner: @runner)
    machines = @runner.environments.includes(:delivered_operations).order(:id).to_a

    assert_no_queries_match(/runner_operations/) { machines.each(&:display_state) }
  end

  private

  def check_session_company_key
    RunnerEnvironment.connection.execute("SET CONSTRAINTS fk_runner_environments_current_session_company IMMEDIATE")
  end
end
