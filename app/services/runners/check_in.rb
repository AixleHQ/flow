# frozen_string_literal: true

module Runners
  # A `manual` machine's host runner reporting itself after a start
  # (docs/design/agent-runtimes/DESIGN.md §6.2; runner/protocol/PROTOCOL.md
  # §5.9): `POST /runner/v1/check-in`, authenticated with the environment's
  # access token, so no token is exchanged.
  #
  # The machine's record keeps what it reported last. `register` records the
  # runner version the machine had when it joined; a machine that updated
  # itself (§14.4) keeps running the new binary under the old record until it
  # checks in, which writes the `X-Aixle-Runner-Version` of the request over it
  # (and the protocol version). The environment's page and the "update
  # available" of the machine health read the version from there.
  #
  #   result = Runners::CheckIn.check_in!(environment, runner_version: "0.2.0", protocol_version: "1",
  #                                       report: { "os" => "linux", "arch" => "amd64", "facts" => { "docker" => "27.1.0" } })
  #   result.environment, result.config, result.update   # update: Runners::Release::Offer, or nil
  #
  # Like `register!`, it takes named parameters and never the request: the
  # gateway checks the headers and the body's shape and maps the body to them
  # (RunnerGateway::V1::CheckInsController). Its refusals are raised as
  # Credentials::Refused.
  module CheckIn
    Result = Data.define(:environment, :config, :update)

    # The keys of the report that a check-in records, when the body has them.
    REPORTED = %w[os arch facts].freeze

    module_function

    # Records the version the machine runs, and the os, arch and facts it
    # reports (a key the report lacks leaves the recorded value as it is), under
    # the environment's row lock, and answers what the runner needs back: the
    # config, and the update the platform offers it under the rule of the
    # `GET ops` answer without ops (Release.update_for, decision 2 of task #217):
    # only while the machine holds no session, only towards the recommended
    # version, and never to a machine that opted out.
    def check_in!(environment, runner_version:, protocol_version:, report: {})
      RunnerEnvironment.transaction do
        # Read fresh: an unregistration that committed since the gateway's
        # check is seen here, and the machine records nothing.
        environment.lock!
        if environment.gone?
          raise Credentials::Refused.new("invalid_token", "The token is unknown, used, revoked or expired.")
        end

        attributes = report.slice(*REPORTED).merge("runner_version" => runner_version, "protocol_version" => protocol_version)
        unless environment.update(attributes)
          raise Credentials::Refused.new("invalid_check_in", environment.errors.full_messages.to_sentence)
        end
      end

      Result.new(environment: environment, config: config,
                 update: Release.update_for(environment, runner_version: runner_version))
    end

    # What the platform tells a runner about its limits. It is for the runner's
    # log: each upload slot of an op carries the `max_bytes` that binds that
    # upload (Uploads).
    def config
      { "upload_max_bytes" => Uploads.limit }
    end
  end
end
