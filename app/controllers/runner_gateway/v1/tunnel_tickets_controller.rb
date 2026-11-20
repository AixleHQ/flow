# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/tunnel-ticket` (docs/design/agent-runtimes/runner-relay.md
    # §3.1; runner/protocol/PROTOCOL.md §5.11): the host runner of a machine asking
    # for the ticket it opens the interactive tunnel with. Authenticated with the
    # environment's access token, through the standard check order, so the throttles
    # of `Rack::Attack` and the refusals of a revoked runner or a flag turned off are
    # the gateway's own. It takes no body. A machine that holds no session answers
    # `409 no_session`.
    class TunnelTicketsController < ApplicationController
      before_action { authenticate(:access) }

      def create
        issued = Runners::TunnelTicket.issue(environment: @credential.runner_environment)
        response.set_header("Cache-Control", "no-store")
        render json: { ticket: issued.ticket, expires_at: issued.expires_at.iso8601 }
      end
    end
  end
end
