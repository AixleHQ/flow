# frozen_string_literal: true

require "test_helper"

class RunnerEnvironmentStateMachineTest < ActiveSupport::TestCase
  ALL_STATES = %w[registered resetting failed gone].freeze

  # The states each event may leave from (DESIGN.md §5.2).
  ALLOWED_FROM = {
    mark_failed: %w[registered resetting failed],
    begin_return_to_service: %w[failed],
    finish_reset: %w[resetting],
    unregister: %w[registered resetting failed gone]
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
    machine = machine_in(:registered)

    assert_raises(AASM::InvalidTransition) { machine.begin_return_to_service! }

    assert_equal "registered", machine.reload.state
  end

  test "mark_failed releases the session's hold and records the reason, cut to the column" do
    machine = machine_in(:registered)
    create(:runner_session, environment: machine)
    assert machine.reload.current_session_id

    machine.mark_failed!("x" * 300)

    machine.reload
    assert_equal "failed", machine.state
    assert_nil machine.current_session_id
    assert_equal 255, machine.state_reason.length
  end

  test "the Return to service events clear the reason, and a finished reset clears the streak" do
    machine = machine_in(:failed, state_reason: "boom", consecutive_failures: 3)

    machine.begin_return_to_service!
    assert_equal [ "resetting", nil ], [ machine.reload.state, machine.state_reason ]

    machine.finish_reset!
    assert_equal [ "registered", 0 ], [ machine.reload.state, machine.consecutive_failures ]
  end

  test "unregister releases the hold, and a machine that is gone stays gone" do
    machine = machine_in(:failed)

    machine.unregister!
    machine.unregister!

    assert_equal "gone", machine.reload.state
    assert_nil machine.current_session_id
  end
end
