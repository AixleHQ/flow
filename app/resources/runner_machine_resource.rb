# frozen_string_literal: true

# A `manual` runner's machine as the runner page lists it, read-only
# (docs/design/agent-runtimes/DESIGN.md §2.5, §11). `state` is the display
# state (RunnerEnvironment#display_state), which depends on the clock.
#
#   runner.environments.map { |machine| RunnerMachineResource.new(machine).to_h }
class RunnerMachineResource < ApplicationResource
  typelize_from RunnerEnvironment

  attributes :id, :key, :display_name, :os, :arch, :runner_version, :state_reason, :last_heartbeat_at, :created_at

  typelize "'online' | 'idle' | 'offline' | 'failed' | 'gone'"
  attribute :state, &:display_state
end
