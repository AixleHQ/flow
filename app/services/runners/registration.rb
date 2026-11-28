# frozen_string_literal: true

module Runners
  # A machine joining and leaving its runner
  # (docs/design/agent-runtimes/DESIGN.md §5.2, §6.2, §6.3, runner-coder.md §8.4):
  # `aixle-runner configure` spends a registration token on a new environment
  # (a `manual` machine) or fills the one the platform made for it (the token is
  # bound to it), and issues its access/refresh pair; `aixle-runner unregister`
  # ends the environment's registration through its adapter.
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
      result = RunnerCredential.transaction do
        Credentials.lock_live_runner!(credential.runner_id)
        # Runner, environment, credentials: the order a Revoke of the machine
        # takes (ManualAdapter#release_machine!, runner-coder.md §6.1, D50), so a
        # bound registration locks its row before the token's.
        bound = lock_bound_environment!(credential) if credential.runner_environment_id
        credential.lock!
        if credential.used? || credential.revoked? || credential.expired?
          raise Credentials::Refused.new("invalid_token", "The registration token is used, revoked or expired.")
        end

        attributes = { display_name: name.to_s.strip, os: os, arch: arch, facts: facts, auto_update: auto_update,
                       runner_version: runner_version, protocol_version: protocol_version, first_seen_ip: remote_ip }
        environment = if bound
          fill_environment!(bound, attributes)
        else
          create_environment!(credential, attributes)
        end

        credential.update!(used_at: Time.current, runner_environment: environment)
        Result.new(environment: environment, pair: Credentials.issue_pair!(environment))
      end
      # The machine's first sign of life, once the registration has committed: it
      # writes the runner's row, which another registration holds `FOR SHARE`
      # (lock_live_runner!) while it waits for this token's row, so inside the
      # transaction two machines racing for one token would deadlock.
      Liveness.record!(runner_id: result.environment.runner_id, environment_id: result.environment.id)
      result
    end

    # What `aixle-runner unregister` does, and what a Revoke of the machine does
    # (DESIGN.md §9.3): the environment's registration ends, through its adapter
    # (`Adapter#end_registration!`, runner-coder.md §6.1), whatever its type.
    # `ended_by` is how the message to a live session says the machine left:
    # `aixle-runner unregister` from the machine, or a Revoke on the runner page.
    def unregister!(environment, ended_by: RunnerEnvironmentStateMachine::UNREGISTERED)
      Adapter.for(environment.runner).end_registration!(environment, ended_by: ended_by)
    end

    # Revoke of one machine from the platform (§9.3): what `unregister!` does,
    # for a machine in any state but `gone`. False for one already `gone`.
    def revoke!(environment)
      return false if RunnerEnvironment.gone.exists?(environment.id)

      unregister!(environment, ended_by: RunnerEnvironmentStateMachine::REVOKED)
      true
    end

    # A `manual` machine registering: a new row, `registered`.
    def create_environment!(credential, attributes)
      environment = RunnerEnvironment.new(
        attributes.merge(runner_id: credential.runner_id, company_id: credential.company_id, origin: :registered,
                         state: :registered, key: "aixle-r#{credential.runner_id}-#{SecureRandom.hex(4)}",
                         created_by_id: credential.created_by_id)
      )
      unless environment.save
        raise Credentials::Refused.new("invalid_registration", environment.errors.full_messages.to_sentence)
      end

      environment
    end
    private_class_method :create_environment!

    # The row a bound token registers into (runner-coder.md §8.4), locked under
    # the runner's lock and before the token's: an `allocated` one of the
    # credential's runner, `provisioning` or `booting`, else the token is refused.
    def lock_bound_environment!(credential)
      environment = RunnerEnvironment.where(id: credential.runner_environment_id, runner_id: credential.runner_id).lock.first
      unless environment&.origin_allocated? && environment.being_built?
        raise Credentials::Refused.new("invalid_token", "The registration token is used, revoked or expired.")
      end

      environment
    end
    private_class_method :lock_bound_environment!

    # A machine registering into the locked row the platform made for it. It
    # records what the machine reports, and moves to `booting` when it was still
    # `provisioning` (the install call had not returned yet; the step that
    # installs re-reads the row and fires no second transition).
    def fill_environment!(environment, attributes)
      if attributes[:display_name].blank?
        raise Credentials::Refused.new("invalid_registration", "Display name can't be blank")
      end

      unless environment.update(attributes)
        raise Credentials::Refused.new("invalid_registration", environment.errors.full_messages.to_sentence)
      end

      environment.finish_build! if environment.provisioning?
      environment
    end
    private_class_method :fill_environment!
  end
end
