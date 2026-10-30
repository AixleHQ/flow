# frozen_string_literal: true

module Runners
  # A `manual` machine joining and leaving its runner
  # (docs/design/agent-runtimes/DESIGN.md §5.2, §6.2, §6.3): `aixle-runner
  # configure` spends a registration token on a new environment and its
  # access/refresh pair, and `aixle-runner unregister` marks the environment
  # `gone` and revokes its credentials.
  module Registration
    Result = Data.define(:environment, :pair)

    module_function

    # `credential` is the registration token's row, already checked by the
    # gateway. It is checked again under its lock, so two machines racing on
    # one token create one environment.
    def register!(credential, name:, os:, arch:, facts:, ephemeral:, runner_version:, protocol_version:)
      if ephemeral
        raise Credentials::Refused.new("ephemeral_not_supported", "Ephemeral registration is not supported yet.")
      end

      credential.with_lock do
        if credential.used? || credential.revoked? || credential.expired?
          raise Credentials::Refused.new("invalid_token", "The registration token is used, revoked or expired.")
        end

        environment = RunnerEnvironment.new(
          runner_id: credential.runner_id, company_id: credential.company_id, origin: :registered,
          state: :registered, key: "aixle-r#{credential.runner_id}-#{SecureRandom.hex(4)}",
          display_name: name, os: os, arch: arch, facts: facts,
          runner_version: runner_version, protocol_version: protocol_version
        )
        unless environment.save
          raise Credentials::Refused.new("invalid_registration", environment.errors.full_messages.to_sentence)
        end

        credential.update!(used_at: Time.current, runner_environment: environment)
        Result.new(environment: environment, pair: Credentials.issue_pair!(environment))
      end
    end

    def unregister!(environment)
      environment.transaction do
        environment.update!(state: :gone)
        now = Time.current
        environment.credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
      end
    end
  end
end
