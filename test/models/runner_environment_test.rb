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

  test "a registered machine needs a name, and an ephemeral one is refused" do
    environment = build(:runner_environment, runner: @runner, display_name: nil, ephemeral: true)

    assert_not environment.valid?
    assert environment.errors.added?(:display_name, :blank)
    assert environment.errors.of_kind?(:ephemeral, :inclusion)
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
    never = create(:runner_environment, runner: @runner)
    stale = create(:runner_environment, runner: @runner, last_heartbeat_at: now - 1.minute)
    at_time = create(:runner_environment, runner: @runner, last_heartbeat_at: now)
    create(:runner_environment, runner: @runner, last_heartbeat_at: now + 1.second)

    assert_equal [ never.id, stale.id, at_time.id ].sort, RunnerEnvironment.not_heard_since(now).pluck(:id).sort
  end

  private

  def check_session_company_key
    RunnerEnvironment.connection.execute("SET CONSTRAINTS fk_runner_environments_current_session_company IMMEDIATE")
  end
end
