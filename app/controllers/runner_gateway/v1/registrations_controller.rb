# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/register` and `DELETE /runner/v1/registration`
    # (docs/design/agent-runtimes/DESIGN.md §6.2, §6.3): `aixle-runner
    # configure` and `aixle-runner unregister` on a `manual` machine.
    class RegistrationsController < ApplicationController
      before_action(only: :create) { authenticate(:registration) }
      before_action(only: :destroy) { authenticate(:access) }

      # Body: {name, os, arch, facts, ephemeral}. The token is spent only by a
      # registration that succeeds.
      def create
        body = request.request_parameters
        result = Runners::Registration.register!(
          @credential,
          name: body["name"].is_a?(String) ? body["name"].strip : nil,
          os: string_or_nil(body["os"]), arch: string_or_nil(body["arch"]),
          facts: body.fetch("facts", {}), ephemeral: ActiveModel::Type::Boolean.new.cast(body["ephemeral"]) == true,
          runner_version: runner_version, protocol_version: PROTOCOL_VERSION
        )
        render_pair(result.pair, status: :created,
                                 environment: RunnerGatewayEnvironmentResource.new(result.environment).to_h)
      end

      # The `409 busy` refusal of §6.2 arrives with the first task that assigns
      # a session to an environment.
      def destroy
        Runners::Registration.unregister!(@credential.runner_environment)
        head :no_content
      end

      private

      def string_or_nil(value)
        value if value.is_a?(String)
      end
    end
  end
end
