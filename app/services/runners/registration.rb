# frozen_string_literal: true

module Runners
  # A `manual` machine joining and leaving its runner
  # (docs/design/agent-runtimes/DESIGN.md §5.2, §6.2, §6.3): `aixle-runner
  # configure` spends a registration token on a new environment and its
  # access/refresh pair, and `aixle-runner unregister` marks the environment
  # `gone`, ends its hold on a session and revokes its credentials.
  #
  # The gateway hands `register!` the request body as it arrived, and every
  # refusal of a registration is raised here, as Credentials::Refused, which
  # the gateway maps to its status (RunnerGateway::V1::ApplicationController).
  module Registration
    Result = Data.define(:environment, :pair)

    # runner_environments.runner_version (RunnerEnvironment's validation).
    RUNNER_VERSION_MAX_LENGTH = 255

    module_function

    # `credential` is the registration token's row, already checked by the
    # gateway. It is checked again under its lock, so two machines racing on
    # one token create one environment, and the runner is locked before it, so
    # a concurrent revocation either refuses this registration or revokes the
    # pair it issued (Credentials.lock_live_runner!).
    #
    # `body` is {name, os, arch, facts, ephemeral, auto_update}, and
    # `runner_version` and `protocol_version` are the request's headers, which
    # the gateway has checked for form (PROTOCOL.md §1). The checks run in the
    # order of PROTOCOL.md §5.1, and the token is spent only by a registration
    # that passes them all:
    #
    # 1. a runner version over 255 characters, which the machine could not
    #    record, is `invalid_registration` whatever the pins say;
    # 2. a runner below the platform's min_version (the `runners.release`
    #    block of config/settings.yml) is `runner_version_unsupported`;
    # 3. `ephemeral: true` is `ephemeral_not_supported`, before the schema;
    # 4. the body is checked against
    #    runner/protocol/schemas/v1/register.request.json;
    # 5. the body is normalized (#attributes) and the machine saved, whose
    #    validation refuses what the schema cannot see, e.g. a blank name.
    #
    # `auto_update: false` is a machine configured with `--no-auto-update`
    # (DESIGN.md §14.4): it is never offered an update.
    def register!(credential, body, runner_version:, protocol_version:)
      body = body.to_h.deep_stringify_keys
      check!(body, runner_version)
      fields = attributes(body)

      RunnerCredential.transaction do
        Credentials.lock_live_runner!(credential.runner_id)
        credential.lock!
        if credential.used? || credential.revoked? || credential.expired?
          raise Credentials::Refused.new("invalid_token", "The registration token is used, revoked or expired.")
        end

        environment = RunnerEnvironment.new(
          runner_id: credential.runner_id, company_id: credential.company_id, origin: :registered,
          state: :registered, key: "aixle-r#{credential.runner_id}-#{SecureRandom.hex(4)}",
          **fields, runner_version: runner_version, protocol_version: protocol_version
        )
        unless environment.save
          raise Credentials::Refused.new("invalid_registration", environment.errors.full_messages.to_sentence)
        end

        credential.update!(used_at: Time.current, runner_environment: environment)
        Result.new(environment: environment, pair: Credentials.issue_pair!(environment))
      end
    end

    # Locks in the one order every issuer and revoker uses: the runner, then
    # the environment, then the credentials (Credentials.rotate!). Holding the
    # runner first keeps this from deadlocking with a runner Revoke, which
    # revokes the same credential rows (Runner#revoke_credentials); a rotation
    # racing this either sees the environment `gone` or has its pair revoked
    # here.
    #
    # A session that holds the machine loses it: its next ops are not created
    # and answer `no_session_container`, so the session fails as one whose
    # container is gone, and its cleanup finds it absent and releases its
    # admission (PROTOCOL.md §8).
    def unregister!(environment)
      RunnerEnvironment.transaction do
        Credentials.lock_live_runner!(environment.runner_id)
        environment.lock!
        environment.update!(state: :gone, current_session_id: nil)
        now = Time.current
        environment.credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
      end
    end

    # Steps 1 to 4 of #register!.
    def check!(body, runner_version)
      if runner_version.length > RUNNER_VERSION_MAX_LENGTH
        raise Credentials::Refused.new("invalid_registration",
                                       "X-Aixle-Runner-Version must be at most #{RUNNER_VERSION_MAX_LENGTH} characters.")
      end

      if Release.unsupported_version?(runner_version)
        raise Credentials::Refused.new("runner_version_unsupported",
                                       "aixle-runner #{runner_version} is no longer supported " \
                                       "(minimum #{Release.min_version}). Update aixle-runner.")
      end

      if ActiveModel::Type::Boolean.new.cast(body["ephemeral"]) == true
        raise Credentials::Refused.new("ephemeral_not_supported", "Ephemeral registration is not supported yet.")
      end

      return if ProtocolSchema.valid?("register.request", body)

      raise Credentials::Refused.new("invalid_registration",
                                     "`name` is required and must be a string, `facts` must be an object, " \
                                     "`auto_update` true or false, and `os` and `arch` at most 255 characters.")
    end

    # The environment's attributes from a body that passed the schema: the
    # name without its surrounding spaces, an `os` or `arch` that is not a
    # string ignored (the schema lets one through, and the protocol says it is
    # ignored), `facts` {} and `auto_update` true when absent.
    def attributes(body)
      { display_name: body["name"].strip, os: string_or_nil(body["os"]), arch: string_or_nil(body["arch"]),
        facts: body.fetch("facts", {}), auto_update: body.fetch("auto_update", true) != false }
    end

    def string_or_nil(value)
      value if value.is_a?(String)
    end
    # register! is the only way in, so it alone decides the order of the checks.
    private_class_method :check!, :attributes, :string_or_nil
  end
end
