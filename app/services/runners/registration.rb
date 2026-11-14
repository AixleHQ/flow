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
    # the machine is saved with its name stripped, whose validations refuse a
    # name blank once stripped or a value over its column with
    # `invalid_registration`.
    # `runner_version` and `protocol_version` are the ones the machine runs
    # and speaks.
    #
    # `remote_ip` is the address the request came from, recorded once as the
    # machine's `first_seen_ip`; the machine's `created_by` is the user who
    # minted the token. Neither is read from the request or checked.
    #
    # `auto_update: false` is a machine configured with `--no-auto-update`
    # (DESIGN.md §14.4): it is never offered an update.
    def register!(credential, name:, os:, arch:, facts:, auto_update:, runner_version:, protocol_version:, remote_ip: nil)
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
          runner_version: runner_version, protocol_version: protocol_version,
          first_seen_ip: remote_ip, created_by_id: credential.created_by_id
        )
        unless environment.save
          raise Credentials::Refused.new("invalid_registration", environment.errors.full_messages.to_sentence)
        end

        credential.update!(used_at: Time.current, runner_environment: environment)
        Liveness.record!(runner_id: environment.runner_id, environment_id: environment.id)
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
    # The machine stops holding its session, if it had one, and the session ends
    # at once with a message that names the machine; its cleanup finds the
    # machine absent and releases its admission (PROTOCOL.md §8). `ended_by` is
    # how the message says the machine left: `aixle-runner unregister` from the
    # machine, or a Revoke on the runner page (DESIGN.md §9.3).
    def unregister!(environment, ended_by: "unregistered")
      held_session_id = release_machine!(environment)
      end_session(environment, held_session_id, ended_by) if held_session_id
    end

    # Revoke of one machine from the platform (§9.3): what `unregister!` does,
    # for a machine in any state but `gone`. False for one already `gone`.
    def revoke!(environment)
      return false if RunnerEnvironment.where(id: environment.id, state: "gone").exists?

      unregister!(environment, ended_by: "revoked")
      true
    end

    # The id of the session the machine held, read under the locks.
    def release_machine!(environment)
      RunnerEnvironment.transaction do
        Credentials.lock_live_runner!(environment.runner_id)
        environment.lock!
        held = environment.current_session_id
        environment.unregister!
        now = Time.current
        environment.credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
        held
      end
    end
    private_class_method :release_machine!

    def end_session(environment, session_id, ended_by)
      session = TerminalSession.find_by(id: session_id)
      return if session.nil? || session.state.in?(TerminalSession::TERMINAL_STATES)

      SessionService.fail_session(
        session: session,
        error_message: "Machine \"#{Machines.label(environment)}\" of runner \"#{environment.runner.name}\" was #{ended_by}."
      )
    end
    private_class_method :end_session
  end
end
