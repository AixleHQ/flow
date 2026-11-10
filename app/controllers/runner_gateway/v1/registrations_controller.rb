# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/register` and `DELETE /runner/v1/registration`
    # (docs/design/agent-runtimes/DESIGN.md §6.2, §6.3): `aixle-runner
    # configure` and `aixle-runner unregister` on a `manual` machine.
    class RegistrationsController < ApplicationController
      # runner_environments.runner_version (RunnerEnvironment's validation).
      RUNNER_VERSION_MAX_LENGTH = 255

      before_action(only: :create) { authenticate(:registration) }
      before_action(only: :destroy) { authenticate(:access) }

      # Body: {name, os, arch, facts, ephemeral, auto_update}, checked against
      # runner/protocol/schemas/v1/register.request.json after the version
      # and ephemeral refusals, which come first (PROTOCOL.md §5.1): a runner
      # version over 255 characters, which the machine could not record, is
      # `invalid_registration` whatever the pins say, and then a runner below
      # the platform's min_version (config/runner_release.yml) is refused with
      # the upgrade message. The token is spent only by a registration that
      # succeeds.
      def create
        if runner_version.length > RUNNER_VERSION_MAX_LENGTH
          return refuse(:unprocessable_entity, "invalid_registration",
                        "X-Aixle-Runner-Version must be at most #{RUNNER_VERSION_MAX_LENGTH} characters.")
        end

        if Runners::Release.unsupported_version?(runner_version)
          return refuse(:bad_request, "runner_version_unsupported",
                        "aixle-runner #{runner_version} is no longer supported (minimum #{Runners::Release.min_version}). " \
                        "Update aixle-runner.")
        end

        body = request.request_parameters
        ephemeral = ActiveModel::Type::Boolean.new.cast(body["ephemeral"]) == true
        if !ephemeral && !Runners::ProtocolSchema.valid?("register.request", body)
          return refuse(:unprocessable_entity, "invalid_registration",
                        "`name` is required and must be a string, `facts` must be an object, `auto_update` true or false, " \
                        "and `os` and `arch` at most 255 characters.")
        end

        result = Runners::Registration.register!(
          @credential,
          name: (body["name"].strip if body["name"].is_a?(String)), os: ignored_unless_string(body["os"]), arch: ignored_unless_string(body["arch"]),
          facts: body.fetch("facts", {}), ephemeral: ephemeral, auto_update: body.fetch("auto_update", true) != false,
          runner_version: runner_version, protocol_version: protocol_version
        )
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

      private

      # The schema lets an `os` or `arch` that is not a string through, and the
      # protocol says it is ignored.
      def ignored_unless_string(value)
        value if value.is_a?(String)
      end
    end
  end
end
