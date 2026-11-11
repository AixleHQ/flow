# frozen_string_literal: true

module Runners
  # A `manual` machine joining and leaving its runner
  # (docs/design/agent-runtimes/DESIGN.md §5.2, §6.2, §6.3): `aixle-runner
  # configure` spends a registration token on a new environment and its
  # access/refresh pair, and `aixle-runner unregister` marks the environment
  # `gone`, ends its hold on a session and revokes its credentials.
  #
  # `register!` takes named parameters, never the request: the gateway checks
  # the headers and the body's shape and maps the body to them
  # (RunnerGateway::V1::RegistrationsController). Its refusals are raised as
  # Credentials::Refused, which the gateway maps to its status
  # (RunnerGateway::V1::ApplicationController).
  module Registration
    Result = Data.define(:environment, :pair)

    module_function

    # `credential` is the registration token's row, already checked by the
    # gateway. It is checked again under its lock, so two machines racing on
    # one token create one environment, and the runner is locked before it, so
    # a concurrent revocation either refuses this registration or revokes the
    # pair it issued (Credentials.lock_live_runner!).
    #
    # The checks run after the gateway's, in the order of PROTOCOL.md §5.1,
    # and the token is spent only by a registration that passes them all:
    # `ephemeral: true` is `ephemeral_not_supported`, and then the machine is
    # saved with its name stripped, whose validations refuse a name blank once
    # stripped or a value over its column with `invalid_registration`.
    # `runner_version` and `protocol_version` are the ones the machine runs
    # and speaks.
    #
    # `auto_update: false` is a machine configured with `--no-auto-update`
    # (DESIGN.md §14.4): it is never offered an update.
    def register!(credential, name:, os:, arch:, facts:, ephemeral:, auto_update:, runner_version:, protocol_version:)
      if ephemeral
        raise Credentials::Refused.new("ephemeral_not_supported", "Ephemeral registration is not supported yet.")
      end

      RunnerCredential.transaction do
        Credentials.lock_live_runner!(credential.runner_id)
        credential.lock!
        if credential.used? || credential.revoked? || credential.expired?
          raise Credentials::Refused.new("invalid_token", "The registration token is used, revoked or expired.")
        end

        environment = RunnerEnvironment.new(
          runner_id: credential.runner_id, company_id: credential.company_id, origin: :registered,
          state: :registered, key: "aixle-r#{credential.runner_id}-#{SecureRandom.hex(4)}",
          display_name: name.to_s.strip, os: os, arch: arch, facts: facts, auto_update: auto_update,
          runner_version: runner_version, protocol_version: protocol_version
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
  end
end
