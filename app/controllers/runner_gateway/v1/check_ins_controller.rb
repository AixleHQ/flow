# frozen_string_literal: true

module RunnerGateway
  module V1
    # `POST /runner/v1/check-in` (docs/design/agent-runtimes/DESIGN.md §6.2;
    # runner/protocol/PROTOCOL.md §5.9): the host runner of a `manual` machine
    # reporting its version, os, arch and facts after every start, authenticated
    # with the environment's access token.
    #
    # Body: {os?, arch?, facts?}, checked against
    # runner/protocol/schemas/v1/check_in.request.json after the version
    # refusals (PROTOCOL.md §5.9) and mapped to the named parameters of
    # Runners::CheckIn.check_in!, which records it. The answer carries the
    # environment, the config the runner needs and, under the rule of the
    # `GET ops` answer without ops, `update`.
    class CheckInsController < ApplicationController
      before_action { authenticate(:access) }
      before_action :check_check_in_version

      def create
        body = request.request_parameters
        unless Runners::ProtocolSchema.valid?("check_in.request", body)
          return refuse(:unprocessable_entity, "invalid_check_in",
                        "`os` and `arch` must be strings of at most 255 characters and `facts` an object.")
        end

        result = Runners::CheckIn.check_in!(
          @credential.runner_environment,
          runner_version: runner_version, protocol_version: protocol_version, report: body.slice(*Runners::CheckIn::REPORTED)
        )
        response.set_header("Cache-Control", "no-store")
        answer = { environment: RunnerGatewayEnvironmentResource.new(result.environment).to_h, config: result.config }
        answer[:update] = RunnerGatewayUpdateResource.new(result.update).to_h if result.update
        render json: answer
      end

      private

      # PROTOCOL.md §5.9, steps 1 and 2: a runner version over 255 characters,
      # which the machine could not record, is `invalid_check_in` whatever the
      # pins say, and then a runner below the platform's min_version is
      # refused with the upgrade message, as `register` refuses it.
      def check_check_in_version
        if runner_version.length > RUNNER_VERSION_MAX_LENGTH
          return refuse(:unprocessable_entity, "invalid_check_in",
                        "X-Aixle-Runner-Version must be at most #{RUNNER_VERSION_MAX_LENGTH} characters.")
        end
        return unless Runners::Release.unsupported_version?(runner_version)

        refuse(:bad_request, "runner_version_unsupported",
               "aixle-runner #{runner_version} is no longer supported (minimum #{Runners::Release.min_version}). " \
               "Update aixle-runner.")
      end
    end
  end
end
