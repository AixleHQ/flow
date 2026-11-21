# frozen_string_literal: true

module Runners
  # What the `runner-relay` service is told about a runner session: the machine
  # that holds it, the route token that names it and the ports that serve it
  # (docs/design/agent-runtimes/runner-relay.md §7.1, §8). The `machine_session`
  # signal and the `holders` endpoint both answer from here, so the two cannot
  # disagree.
  #
  #   Runners::RelayRoute.describe(session, environment_id: 7)
  #   # => { session_id: 123, environment_id: 7, state: "ready", route_token: "…", ports: { "tty" => 7681, … } }
  module RelayRoute
    module_function

    # `environment_id` is the machine the caller means: the one the signal is
    # about, or, for a question, the one that holds the session now
    # (Machines.held_by), nil when none does.
    def describe(session, environment_id:)
      {
        session_id: session.id,
        environment_id: environment_id,
        state: session.state,
        route_token: session.route_token,
        ports: Tunnel.ports(session)
      }
    end
  end
end
