# frozen_string_literal: true

# An environment as the runner gateway returns it to `aixle-runner`. The runner
# protocol is snake_case (docs/design/agent-runtimes/DESIGN.md §6.4), unlike the
# camelCase of ApplicationResource, and it is not a browser type.
class RunnerGatewayEnvironmentResource
  include Alba::Resource

  transform_keys :none

  attributes :id, :key, :display_name, :state
end
