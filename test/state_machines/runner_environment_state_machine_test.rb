# frozen_string_literal: true

require "test_helper"

class RunnerEnvironmentStateMachineTest < ActiveSupport::TestCase
  ALL_STATES = %w[registered failed gone].freeze

  # The states each event may leave from (DESIGN.md §5.2).
  ALLOWED_FROM = {
    mark_failed: %w[registered failed],
    unregister: %w[registered failed gone]
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

  test "a machine has no resetting state, and failed is final: no event leaves it but unregister" do
    assert_not_includes RunnerEnvironment.aasm.states.map { |state| state.name.to_s }, "resetting"
    assert_equal [ :unregister ], machine_in(:failed).aasm.events(permitted: true).map(&:name) - [ :mark_failed ]
  end

  test "unregister releases the hold, and a machine that is gone stays gone" do
    machine = machine_in(:failed)

    machine.unregister!
    machine.unregister!

    assert_equal "gone", machine.reload.state
    assert_nil machine.current_session_id
  end
end
