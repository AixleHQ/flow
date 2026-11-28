# frozen_string_literal: true

require "test_helper"

class RunnerEnvironmentStateMachineTest < ActiveSupport::TestCase
  ALL_STATES = %w[registered provisioning booting idle failed tearing_down gone].freeze

  # The states each event may leave from (DESIGN.md §5.2, runner-coder.md §6).
  ALLOWED_FROM = {
    mark_failed: %w[registered provisioning booting idle tearing_down failed],
    unregister: %w[registered failed gone],
    finish_build: %w[provisioning],
    check_in: %w[booting],
    begin_teardown: %w[provisioning booting idle failed],
    finish_teardown: %w[tearing_down]
  }.freeze

  setup do
    @runner = create(:runner, :manual)
  end

  def machine_in(state, **attributes)
    create(:runner_environment, runner: @runner, state: state, **attributes)
  end

  test "a new machine is registered" do
    assert_equal "registered", RunnerEnvironment.new.state
  end

  test "each event is allowed from exactly its states" do
    ALLOWED_FROM.each do |event, allowed|
      ALL_STATES.each do |state|
        may = machine_in(state).public_send(:"may_#{event}?")
        assert_equal allowed.include?(state), may, "#{event} from #{state}"
      end
    end
  end

  test "a refused transition raises and leaves the machine as it was" do
    machine = machine_in(:gone)

    assert_raises(AASM::InvalidTransition) { machine.mark_failed! }

    assert_equal "gone", machine.reload.state
  end

  test "mark_failed releases the session's hold and records the reason, cut to the column" do
    machine = machine_in(:registered)
    create(:runner_session, :holding, environment: machine)
    assert machine.reload.current_session_id

    machine.mark_failed!("x" * 300)

    machine.reload
    assert_equal "failed", machine.state
    assert_nil machine.current_session_id
    assert_equal 255, machine.state_reason.length
  end

  test "an allocated environment goes from provisioning through booting to idle, and a check-in is not a registration" do
    environment = machine_in(:provisioning, origin: :allocated)

    environment.finish_build!
    assert_equal "booting", environment.reload.state

    environment.check_in!
    assert_equal "idle", environment.reload.state
    assert environment.in_service?
  end

  test "a failed environment is torn down and then gone, and keeps the reason it failed with" do
    environment = machine_in(:booting, origin: :allocated)
    environment.mark_failed!("the install failed")

    environment.begin_teardown!
    assert_equal "tearing_down", environment.reload.state
    assert_equal "the install failed", environment.state_reason

    environment.finish_teardown!
    assert_equal "gone", environment.reload.state
    assert_equal "the install failed", environment.state_reason
  end

  test "a teardown releases the hold and records the reason it is given" do
    environment = machine_in(:idle, origin: :allocated)
    create(:runner_session, :holding, environment: environment)
    assert environment.reload.current_session_id

    environment.begin_teardown!("revoked")

    environment.reload
    assert_equal "tearing_down", environment.state
    assert_nil environment.current_session_id
    assert_equal "revoked", environment.state_reason
  end

  test "any state but gone can fail, which releases the hold" do
    (ALL_STATES - %w[gone]).each do |state|
      environment = machine_in(state)
      create(:runner_session, :holding, environment: environment)

      environment.mark_failed!("it failed in #{state}")

      assert_equal "failed", environment.reload.state, state
      assert_nil environment.current_session_id, state
    end
  end

  test "a machine has no resetting state, and nothing returns a failed one to service: it only fails again, is torn down or leaves" do
    assert_not_includes RunnerEnvironment.aasm.states.map { |state| state.name.to_s }, "resetting"
    targets = machine_in(:failed).aasm.events(permitted: true).flat_map { |event| event.transitions.map(&:to) }

    assert_equal %i[failed gone tearing_down], targets.uniq.sort
  end

  test "unregister releases the hold, and a machine that is gone stays gone" do
    machine = machine_in(:failed)

    machine.unregister!
    machine.unregister!

    assert_equal "gone", machine.reload.state
    assert_nil machine.current_session_id
  end
end
