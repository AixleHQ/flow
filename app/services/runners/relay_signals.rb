# frozen_string_literal: true

module Runners
  # The signals the platform sends the `runner-relay` service, so it learns without
  # long requests which session each machine holds and when to let go
  # (docs/design/agent-runtimes/runner-relay.md §8.1). One channel, `runner_relay`,
  # on Action Cable's pub/sub (Redis), JSON messages told apart by their `type`:
  #
  #   {"type":"machine_session","environment_id":7,"session_id":123|null,"route_token":"…","ports":{…}}
  #   {"type":"session_ended","session_id":123}
  #   {"type":"machine_revoked","environment_id":7}
  #
  # Each is published once the surrounding transaction has committed
  # (ActiveRecord.after_all_transactions_commit, as Operations#wake does): one
  # that rolled back sends nothing. A publish that fails is logged and swallowed
  # (BestEffortBroadcast).
  # Redis pub/sub loses messages anyway, and the relay's reconcile pass (§8.3, the
  # `checks` endpoint) is what guarantees it converges.
  module RelaySignals
    CHANNEL = "runner_relay"

    module_function

    # A session took the machine, or left it (`session_id` nil). The session's
    # route token and ports are read when the signal is sent, after the commit.
    def machine_session(environment_id, session_id)
      deliver("machine_session") do
        session = TerminalSession.find_by(id: session_id) if session_id
        route = RelayRoute.describe(session, environment_id: environment_id) if session
        { environment_id: environment_id, session_id: session&.id, route_token: route&.fetch(:route_token), ports: route&.fetch(:ports) }
      end
    end

    # A runner session left `ready`.
    def session_ended(session_id)
      deliver("session_ended") { { session_id: session_id } }
    end

    # The machine left for good, or its runner was revoked or deleted.
    def machine_revoked(environment_id)
      deliver("machine_revoked") { { environment_id: environment_id } }
    end

    # Builds the message and publishes it after the commit. Building it can fail
    # too (a session deleted meanwhile): it is swallowed the same way, and logged
    # with the signal's `type`.
    def deliver(type, &message)
      ActiveRecord.after_all_transactions_commit { publish(type, &message) }
    end

    def publish(type)
      BestEffortBroadcast.call(CHANNEL, context: "[Runners::RelaySignals] #{type} signal") { { type: type, **yield } }
    end
    private_class_method :deliver, :publish
  end
end
