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

    # Four queries however many machines are asked about.
    def valid(machines)
      environments = RunnerEnvironment.where(id: machines.pluck("environment_id")).index_by(&:id)
      ready = TerminalSession.ready.where(id: environments.values.filter_map(&:current_session_id)).ids.to_set
      live_runners = Runner.not_retired.where(id: environments.values.map(&:runner_id).uniq).ids.to_set
      companies = Company.where(id: environments.values.map(&:company_id).uniq).index_by(&:id)
      enabled = {}

      machines.map do |machine|
        environment = environments[machine["environment_id"]]
        next false unless environment&.registered? && environment.current_session_id == machine["session_id"]
        next false unless ready.include?(environment.current_session_id) && live_runners.include?(environment.runner_id)

        enabled.fetch(environment.company_id) do
          enabled[environment.company_id] = Feature.enabled?(:external_runners, company: companies[environment.company_id])
        end
      end
    end
  end
end
