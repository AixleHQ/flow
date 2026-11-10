# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/register` and `DELETE /runner/v1/registration`
    # (docs/design/agent-runtimes/DESIGN.md §6.2, §6.3): `aixle-runner
    # configure` and `aixle-runner unregister` on a `manual` machine.
    class RegistrationsController < ApplicationController
      before_action(only: :create) { authenticate(:registration) }
      before_action(only: :destroy) { authenticate(:access) }

      # Body: {name, os, arch, facts, ephemeral, auto_update}.
      # Runners::Registration.register! checks it, with the runner version,
      # and raises each refusal in the order of PROTOCOL.md §5.1, which the
      # base controller maps to its status.
      def create
        result = Runners::Registration.register!(@credential, request.request_parameters,
                                                 runner_version: runner_version, protocol_version: protocol_version)
        render_pair(result.pair, status: :created,
                                 environment: RunnerGatewayEnvironmentResource.new(result.environment).to_h)
      end

      # A machine unregistered during a session is not refused: `409 busy` is
      # not built (runner/protocol/PROTOCOL.md §8). The machine stops holding
      # the session, whose next ops answer `no_session_container`, so the
      # session fails as one whose container is gone (Runners::Registration).
      def destroy
        Runners::Registration.unregister!(@credential.runner_environment)
        head :no_content
      end
    end
  end
end
