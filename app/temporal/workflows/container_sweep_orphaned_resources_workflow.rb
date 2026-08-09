# frozen_string_literal: true

module Workflows
  # ContainerSweepOrphanedResourcesWorkflow — garbage-collects the runtime
  # objects (Pod, Service, IngressRoute, Middlewares) of agent sessions that are
  # finished, failed, or gone from the database. Wired into
  # `app/temporal/schedules.yml` so the project's existing Temporal cron drives
  # it.
  #
  # Correctness does not depend on the cadence: the happy path still tears its
  # own objects down in `ContainerRuntime#remove_container`, and the sweep is
  # idempotent — a missed run leaves the same garbage for the next one, a doubled
  # run finds nothing the first already deleted. The cadence only decides how
  # long a dead node's leftovers keep answering 503 on a session URL.
  class ContainerSweepOrphanedResourcesWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.container_sweep_orphaned_resources_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
