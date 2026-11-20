# frozen_string_literal: true

module Runners
  # The relay's reconcile pass (docs/design/agent-runtimes/runner-relay.md §8.2, §8.3):
  # one batched question for all the machines it has connected, and what each holds.
  #
  #   Runners::RelayChecks.valid([{ "environment_id" => 7, "session_id" => 123 }])  # => [true]
  #
  # A machine is valid when it is registered, its runner is not revoked or deleted, the
  # company's `external_runners` flag is on, it still holds that session, and that
  # session is `ready`. The answers are in the order of the questions. Whatever is
  # unknown to the platform is `false`.
  module RelayChecks
    module_function

    def valid(machines)
      environments = RunnerEnvironment.where(id: machines.pluck("environment_id")).includes(:runner, :company, :current_session)
                                      .index_by(&:id)
      flags = {}
      machines.map do |machine|
        environment = environments[machine["environment_id"]]
        environment.present? && valid?(environment, machine["session_id"], flags)
      end
    end

    def valid?(environment, session_id, flags)
      return false unless environment.registered? && environment.current_session_id == session_id
      return false unless environment.current_session&.ready?

      runner = environment.runner
      return false if runner.deleted_at || runner.status == "revoked"

      flags.fetch(environment.company_id) { flags[environment.company_id] = Feature.enabled?(:external_runners, company: environment.company) }
    end
    private_class_method :valid?
  end
end
