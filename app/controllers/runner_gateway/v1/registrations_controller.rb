# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/register` and `DELETE /runner/v1/registration`
    # (docs/design/agent-runtimes/DESIGN.md §6.2, §6.3): `aixle-runner
    # configure` and `aixle-runner unregister` on a `manual` machine.
    class RegistrationsController < ApplicationController
      before_action(only: :create) { authenticate(:registration) }
      before_action :check_registration_version, only: :create
      before_action(only: :destroy) { authenticate(:access) }

      # Body: {name, os, arch, facts, auto_update}, checked against
      # runner/protocol/schemas/v1/register.request.json after the version
      # refusals (PROTOCOL.md §5.1); fields the schema does not know are
      # ignored. The body is then mapped by the protocol's wire rules: an
      # absent `os` or `arch` is nil, `facts` is {} and `auto_update` true when
      # absent.
      def create
        body = request.request_parameters
        unless Runners::ProtocolSchema.valid?("register.request", body)
          return refuse(:unprocessable_entity, "invalid_registration",
                        "`name` is required and must be a string, `facts` must be an object, " \
                        "`auto_update` true or false, and `os` and `arch` strings of at most 255 characters.")
        end

        result = Runners::Registration.register!(
          @credential,
          name: body["name"], os: body["os"], arch: body["arch"],
          facts: body.fetch("facts", {}),
          auto_update: body.fetch("auto_update", true) != false,
          runner_version: runner_version, protocol_version: protocol_version,
          remote_ip: request.remote_ip
        )
        render_pair(result.pair, status: :created,
                                 environment: RunnerGatewayEnvironmentResource.new(result.environment).to_h)
      end

      # A machine unregistered during a session is not refused: `409 busy` is
      # not built (runner/protocol/PROTOCOL.md §8). The machine stops holding
      # the session, which ends at once and has its admission released
      # (Runners::Registration).
      def destroy
        Runners::Registration.unregister!(@credential.runner_environment)
        head :no_content
      end
    end
  end
end
