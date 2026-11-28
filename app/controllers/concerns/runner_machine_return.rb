# frozen_string_literal: true

# Revoke for a machine of a `manual` runner, for the two machines controllers
# (docs/design/agent-runtimes/DESIGN.md §9.3). The controller
# has already found the runner in its own scope and the policy has authorized
# the action; the machine is looked up among that runner's own.
module RunnerMachineReturn
  extend ActiveSupport::Concern

  private

  # Revoke of one machine (§9.3): the machine is `gone` and its credentials are
  # revoked, and the session it held ends. A machine already `gone`, or whose
  # runner was revoked meanwhile, has nothing left to revoke.
  def revoke_machine(runner)
    machine = runner.environments.find(params[:id])
    name = Runners::Machines.label(machine)
    if Runners::Registration.revoke!(machine)
      { notice: "#{name} is revoked. Its credentials stopped working; remove what is left on the machine yourself." }
    else
      { alert: "#{name} is already gone." }
    end
  rescue Runners::Credentials::Refused
    { alert: "This runner is revoked, so its machines are no longer usable." }
  end
end
