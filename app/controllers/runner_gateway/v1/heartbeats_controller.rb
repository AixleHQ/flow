# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/heartbeat` (docs/design/agent-runtimes/DESIGN.md §6.2,
    # §6.7; runner/protocol/PROTOCOL.md §5.10): the host runner of a `manual`
    # machine saying it is alive while no poll is outstanding, which is while
    # it runs an op. Authenticated with the environment's access token and
    # answered `204`.
    #
    # The request's body is empty in protocol 1 and is not read. The heartbeat
    # is recorded by the authentication every request of a machine goes through
    # (Runners::Liveness.record!), so the action has nothing to add.
    class HeartbeatsController < ApplicationController
      before_action { authenticate(:access) }

      def create
        head :no_content
      end
    end
  end
end
