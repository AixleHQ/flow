# frozen_string_literal: true

# Return to service for a machine of a `manual` runner, for the two runners
# controllers (docs/design/agent-runtimes/DESIGN.md §5.2, §7.2). The controller
# has already found the runner in its own scope and the policy has authorized
# the action; the machine is looked up among that runner's own.
module RunnerMachineReturn
  extend ActiveSupport::Concern

  private

  # The flash for the redirect: the machine is `resetting` now, or it was not
  # `failed`, or its runner is not `manual`, and nothing was sent.
  def return_machine_to_service(runner)
    machine = runner.environments.find(params[:machine_id])
    name = Runners::Machines.label(machine)
    if Runners::Machines.return_to_service!(machine)
      { notice: "#{name} is being reset. It takes sessions again once the reset succeeds." }
    else
      { alert: "#{name} is not failed, so there is nothing to return to service." }
    end
  rescue Runners::Machines::NotManual => e
    { alert: e.message }
  end
end
