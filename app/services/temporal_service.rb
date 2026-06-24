require "temporalio/client"
require "temporalio/worker"
require "temporalio/testing/workflow_environment"

class TemporalService
  class << self
    # Data
    def client
      @client ||= Temporalio::Client.connect(address, namespace, logger: Rails.logger)
    end

    def worker
      @worker ||= begin
        wfs = workflows
        eager_load_workflow_registries!(wfs)

        Temporalio::Worker.new(
          client: client,
          task_queue: Settings.temporal.task_queue,
          activities: activities,
          workflows: wfs,
          interceptors: interceptors,
          graceful_shutdown_period: worker_graceful_shutdown_period,
          tuner: Temporalio::Worker::Tuner.create_fixed(
            activity_slots: (ENV.fetch("RAILS_MAX_THREADS", 5).to_i * 0.8).ceil
          ),
        )
      end
    end

    def address
      @address ||= "#{Settings.temporal.host}:#{Settings.temporal.port}"
    end

    def namespace
      @namespace ||= Settings.temporal.namespace
    end

    def interceptors
      @interceptors ||= [ Interceptors::SentryInterceptor.new ]
    end

    def activities
      @activities ||= begin
        Dir[Rails.root.join("app/temporal/activities/**/*.rb")].each { |f| require f }
        Activities::Base.descendants
      end
    end

    def workflows
      @workflows ||= begin
        Dir[Rails.root.join("app/temporal/workflows/**/*.rb")].each { |f| require f }
        Workflows::Base.descendants
      end
    end

    def schedule_definitions
      @schedule_definitions ||= Hashie::Mash.new(YAML.load_file(Rails.root.join("app/temporal/schedules.yml"))).schedules || []
    end

    def workflow_id(workflow, input)
      "#{workflow.name}-#{input.hash.abs}"
    end

    # Actions
    def sync_schedules
      delete_schedules
      schedule_definitions.each do |schedule_def|
        create_schedule(schedule_def)
      end
    end

    def start_workflow(workflow, input, options = {})
      id = options[:id] || workflow_id(workflow, input)
      execution_timeout = options[:execution_timeout]

      handle = with_test_environment_handling do |cl|
        workflow_options = { id: id, task_queue: workflow.owner }
        workflow_options[:execution_timeout] = execution_timeout if execution_timeout

        cl.start_workflow(workflow.name, input, **workflow_options)
      end

      return { ok: false, error: "Temporal is disabled" } if handle.nil?

      Rails.logger.info("[Temporal] ✅ Workflow #{id} queued: #{handle.id}")

      { ok: true, workflow_id: handle.id, run_id: handle.run_id, handle: handle }
    rescue Temporalio::Error => e
      { ok: false, error: e.message }
    end

    def execute_workflow(workflow, input, options = {})
      id = options[:id] || workflow_id(workflow, input)
      execution_timeout = options[:execution_timeout]

      result = with_test_environment_handling do |cl|
        workflow_options = { id: id, task_queue: workflow.owner }
        workflow_options[:execution_timeout] = execution_timeout if execution_timeout

        cl.execute_workflow(workflow.name, input, **workflow_options)
      end

      return nil if result.nil? && !enabled?

      Rails.logger.info("[Temporal] ✅ Workflow #{id} completed: #{result}")
      result
    rescue Temporalio::Error => e
      Rails.logger.info("[Temporal] ❌ Workflow #{id} execution failed: #{e.message}")
      raise
    end

    # Send signal to running workflow
    def send_signal(workflow_id, signal_name, payload = nil)
      return { ok: false, error: "Temporal is disabled" } unless enabled?

      with_test_environment_handling do |cl|
        handle = cl.workflow_handle(workflow_id)
        handle.signal(signal_name.to_s, payload)
      end

      Rails.logger.info("[Temporal] ✅ Signal '#{signal_name}' sent to workflow #{workflow_id}")
      { ok: true }
    rescue Temporalio::Error => e
      Rails.logger.error("[Temporal] ❌ Failed to send signal: #{e.message}")
      { ok: false, error: e.message }
    end

    # Cancel running workflow
    def cancel_workflow(workflow_id)
      return { ok: false, error: "Temporal is disabled" } unless enabled?

      with_test_environment_handling do |cl|
        handle = cl.workflow_handle(workflow_id)
        handle.cancel
      end

      Rails.logger.info("[Temporal] ✅ Workflow #{workflow_id} cancelled")
      { ok: true }
    rescue Temporalio::Error => e
      Rails.logger.error("[Temporal] ❌ Failed to cancel workflow: #{e.message}")
      { ok: false, error: e.message }
    end

    def create_schedule(schedule_def)
      workflow = TemporalWorkflowRegistry.workflows[schedule_def.workflow]
      id = "#{workflow.name}-#{DateTime.now.to_fs(:db)}"

      with_test_environment_handling do |cl|
        cl.create_schedule(
          workflow.name,
          Temporalio::Client::Schedule.new(
            action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
              workflow.name, nil, id: id, task_queue: workflow.owner
            ),
            spec: Temporalio::Client::Schedule::Spec.new(
              cron_expressions: [ schedule_def.cron ],
            ),
            policy: Temporalio::Client::Schedule::Policy.new(
              overlap: schedule_overlap_policy(schedule_def)
            ),
          )
        ) if schedule_def.enabled
      end
    rescue Temporalio::Error::ScheduleAlreadyRunningError => e
      Rails.logger.warn("[Temporal] Schedule #{workflow&.name} already exists: #{e.message}")
    end

    # Per-schedule overlap policy. Defaults to BUFFER_ONE (queue one), but a
    # schedule can opt into SKIP via `overlap: skip` in schedules.yml — used by the
    # outbox relay, which is idempotent and must never run two drains at once.
    def schedule_overlap_policy(schedule_def)
      if schedule_def.overlap.to_s == "skip"
        Temporalio::Client::Schedule::OverlapPolicy::SKIP
      else
        Temporalio::Client::Schedule::OverlapPolicy::BUFFER_ONE
      end
    end

    def delete_schedules
      with_test_environment_handling do |cl|
        ids = cl.list_schedules.map { |x| x.id }
        ids.each do |id|
          cl.schedule_handle(id).delete
        rescue Temporalio::Error::RPCError => e
          Rails.logger.warn("[Temporal] Failed to delete schedule #{id}: #{e.message}")
        end
      end
    end

    def delete_schedule(schedule_def)
      workflow = TemporalWorkflowRegistry.workflows[schedule_def.workflow]
      with_test_environment_handling do |cl|
        cl.schedule_handle(workflow.name).delete
      end
    rescue Temporalio::Error::RPCError => e
    end

    # Create a dynamic, per-record schedule (e.g. for a user's schedule trigger)
    # with a caller-supplied stable schedule_id and input. Fires the
    # ScheduledTriggerWorkflow on the given cron (optionally in a timezone).
    def create_binding_schedule(schedule_id:, cron:, input:, timezone: nil)
      workflow = TemporalWorkflowRegistry.workflows["scheduled_trigger_workflow"]
      return if workflow.nil?

      with_test_environment_handling do |cl|
        cl.create_schedule(
          schedule_id,
          Temporalio::Client::Schedule.new(
            action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
              workflow.name, input, id: "#{schedule_id}-run", task_queue: workflow.owner
            ),
            spec: Temporalio::Client::Schedule::Spec.new(
              cron_expressions: [ cron ],
              time_zone_name: timezone.presence
            ),
            policy: Temporalio::Client::Schedule::Policy.new(
              overlap: Temporalio::Client::Schedule::OverlapPolicy::SKIP
            )
          )
        )
      end
    rescue Temporalio::Error::ScheduleAlreadyRunningError => e
      Rails.logger.warn("[Temporal] Schedule #{schedule_id} already exists: #{e.message}")
    end

    def delete_binding_schedule(schedule_id)
      with_test_environment_handling do |cl|
        cl.schedule_handle(schedule_id).delete
      end
    rescue Temporalio::Error::RPCError => e
      Rails.logger.warn("[Temporal] Failed to delete schedule #{schedule_id}: #{e.message}")
    end

    def enabled?
      Settings.temporal.enabled.to_s == "true"
    end

    def worker_graceful_shutdown_period
      Settings.temporal.worker_graceful_shutdown_period.to_i
    end

    private

    # Pre-resolve TemporalWorkflowRegistry lookups so workflows
    # never trigger autoloading inside the Temporal sandbox.
    def eager_load_workflow_registries!(workflow_classes)
      TemporalWorkflowRegistry.workflows
      workflow_classes.each(&:preload_activities!)
    end

    def with_test_environment_handling(&block)
      if Rails.env.test?
        Temporalio::Testing::WorkflowEnvironment.start_local do |env|
          yield(env.client)
        end
      elsif enabled?
        yield(client)
      else
        Rails.logger.info("[Temporal] Skipped: Temporal is disabled")
        nil
      end
    end
  end
end
