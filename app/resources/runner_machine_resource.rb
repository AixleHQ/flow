# frozen_string_literal: true

# A `manual` runner's machine as the runner page lists it, read-only
# (docs/design/agent-runtimes/DESIGN.md §2.5, §11). `state` is the display
# state, which depends on the clock and on the machine's delivered ops, so the
# caller works it out for the whole list (Runners::Liveness.states) and passes
# it in:
#
#   RunnerMachineResource.new(machine, params: { states: Runners::Liveness.states(machines) }).to_h
class RunnerMachineResource < ApplicationResource
  typelize_from RunnerEnvironment

  attributes :id, :key, :display_name, :os, :arch, :runner_version, :state_reason, :last_heartbeat_at, :created_at

  typelize "'online' | 'idle' | 'offline' | 'failed' | 'gone'"
  attribute :state do |machine|
    params.fetch(:states).fetch(machine.id)
  end
end
