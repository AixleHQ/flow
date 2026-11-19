# frozen_string_literal: true

require "test_helper"

class RunnerMachineResourceTest < ActiveSupport::TestCase
  test "revokedByOperator is true for a machine revoked from the runner page and false for one that unregistered" do
    runner = create(:runner, :manual)
    revoked = create(:runner_environment, runner: runner)
    revoked.unregister!(RunnerEnvironmentStateMachine::REVOKED)
    unregistered = create(:runner_environment, runner: runner)
    unregistered.unregister!

    assert RunnerMachineResource.new(revoked).to_h["revokedByOperator"]
    refute RunnerMachineResource.new(unregistered).to_h["revokedByOperator"]
  end
end
