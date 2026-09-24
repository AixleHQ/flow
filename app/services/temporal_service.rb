# frozen_string_literal: true

require "temporalio/client"
require "temporalio/worker"

class TemporalService
  class << self
    # The test suite points this at a local test server (test/test_helper.rb)
    # instead of this class asking which environment it runs in.
    attr_writer :connection

    # Data
    def client
      @client ||= Temporalio::Client.connect(address, namespace, logger: Rails.logger, data_converter: data_converter)
    end

    # The SDK's JSON converter defaults to `create_additions: true`, which revives any
    # payload hash naming a "json_class" as an instance of that class. No payload of
    # ours is such an object, and json 3 removed the option (see the Gemfile's pin).
    def data_converter
      @data_converter ||= Temporalio::Converters::DataConverter.new(
        payload_converter: Temporalio::Converters::PayloadConverter.new_with_defaults(json_parse_options: {})
      )
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
            activity_slots: worker_activity_slots
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

    # Every start names its workflow id. There is no fallback: Object#hash is
    # seeded per process, so an id derived from the input differs between pods and
    # deduplicates nothing.
    def workflow_id!(options)
      options[:id].presence || raise(ArgumentError, "a workflow start needs an explicit id:")
    end

    # Actions

    # Converges Temporal onto schedules.yml: every enabled definition is updated
    # in place or created, and only a static schedule that is no longer defined
    # is deleted — never delete-and-recreate, which loses ticks in the gap on every
    # boot of every worker pod.
    #
    # Idempotent, so concurrent boots are harmless. Each schedule is attempted
    # on its own and the failures are reported together; the worker still
    # starts, because a missing housekeeping schedule is not worth stopping
    # every workflow for — QueueHealthCheck watches the symptoms either way.
    def sync_schedules
      failures = []
      keep = []
      schedule_definitions.select(&:enabled).each do |definition|
        # Kept even when its update fails below: a schedule that could not be
        # updated is still wanted, and must not be pruned for it.
        keep << static_schedule_id(definition)
        upsert_schedule(definition)
      rescue StandardError => e
        failures << "#{definition.workflow}: #{e.class}: #{e.message}"
      end
      failures.concat(prune_schedules(keep: keep))
      # Per-binding schedule triggers live only in the database; a redeploy has
      # to be able to restore them too.
      ScheduleReconciler.reconcile_all
      report_schedule_failures(failures)
      failures
    end

    def start_workflow(workflow, input, options = {})
      id = workflow_id!(options)
      execution_timeout = options[:execution_timeout]

      handle = with_client do |cl|
        workflow_options = { id: id, task_queue: workflow.owner }
        workflow_options[:execution_timeout] = execution_timeout if execution_timeout

        if options[:reject_duplicate]
          workflow_options[:id_reuse_policy] = Temporalio::WorkflowIDReusePolicy::REJECT_DUPLICATE
        end
        cl.start_workflow(workflow.name, input, **workflow_options)
      end

      return { ok: false, error: "Temporal is disabled" } if handle.nil?

      Rails.logger.info("[Temporal] ✅ Workflow #{id} queued: #{handle.id}")

      { ok: true, workflow_id: handle.id, run_id: handle.run_id, handle: handle }
    rescue Temporalio::Error::WorkflowAlreadyStartedError => e
      return { ok: true, workflow_id: id, run_id: e.run_id } if options[:reject_duplicate]
      { ok: false, error: e.message }
    rescue Temporalio::Error => e
      { ok: false, error: e.message, error_class: e.class.name }
    end

    def execute_workflow(workflow, input, options = {})
      id = workflow_id!(options)
      execution_timeout = options[:execution_timeout]

      result = with_client do |cl|
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

      with_client do |cl|
        handle = cl.workflow_handle(workflow_id)
        handle.signal(signal_name.to_s, payload)
      end

      Rails.logger.info("[Temporal] ✅ Signal '#{signal_name}' sent to workflow #{workflow_id}")
      { ok: true }
    rescue Temporalio::Error => e
      Rails.logger.error("[Temporal] ❌ Failed to send signal: #{e.message}")
      { ok: false, error: e.message }
    end

    # True if the workflow execution is still open (running), false if it has
    # closed (completed/failed/cancelled/terminated) or doesn't exist. Used to
    # avoid signaling a closed execution, which fails silently otherwise.
    def workflow_open?(workflow_id)
      execution_state(workflow_id) == :running
    end

    # What Temporal knows about an execution: :running, :closed, :not_found, or
    # :unknown when it could not be asked. Anything that acts on "dead" must
    # treat :unknown as alive.
    def execution_state(workflow_id)
      return :unknown unless enabled?

      # Captured rather than returned: in test the block runs inside
      # WorkflowEnvironment.start_local, whose return value is not the block's.
      status = nil
      with_client { |cl| status = cl.workflow_handle(workflow_id).describe.status }
      status == Temporalio::Client::WorkflowExecutionStatus::RUNNING ? :running : :closed
    rescue Temporalio::Error::RPCError => e
      return :not_found if e.code == Temporalio::Error::RPCError::Code::NOT_FOUND

      Rails.logger.warn("[Temporal] Failed to describe workflow #{workflow_id}: #{e.message}")
      :unknown
    rescue Temporalio::Error => e
      Rails.logger.warn("[Temporal] Failed to describe workflow #{workflow_id}: #{e.message}")
      :unknown
    end

    # Cancel running workflow
    def cancel_workflow(workflow_id)
      return { ok: false, error: "Temporal is disabled" } unless enabled?

      with_client do |cl|
        handle = cl.workflow_handle(workflow_id)
        handle.cancel
      end

      Rails.logger.info("[Temporal] ✅ Workflow #{workflow_id} cancelled")
      { ok: true }
    rescue Temporalio::Error => e
      Rails.logger.error("[Temporal] ❌ Failed to cancel workflow: #{e.message}")
      { ok: false, error: e.message }
    end

    # Updates the static schedule in place, keeping whatever pause an operator
    # set on it, or creates it when Temporal has none.
    def upsert_schedule(schedule_def)
      desired = static_schedule(schedule_def)
      id = static_schedule_id(schedule_def)

      with_client do |cl|
        cl.schedule_handle(id).update do |input|
          Temporalio::Client::Schedule::Update.new(schedule: desired.with(state: input.description.schedule.state))
        end
      rescue Temporalio::Error::RPCError => e
        raise unless e.code == Temporalio::Error::RPCError::Code::NOT_FOUND

        create_static_schedule(cl, id, desired)
      end
    end

    def create_schedule(schedule_def)
      return unless schedule_def.enabled

      with_client do |cl|
        create_static_schedule(cl, static_schedule_id(schedule_def), static_schedule(schedule_def))
      end
    end

    def static_schedule_id(schedule_def)
      workflow = TemporalWorkflowRegistry.workflows[schedule_def.workflow]
      raise ArgumentError, "schedules.yml names an unknown workflow: #{schedule_def.workflow}" unless workflow

      workflow.name
    end

    def static_schedule(schedule_def)
      workflow = TemporalWorkflowRegistry.workflows[schedule_def.workflow]
      Temporalio::Client::Schedule.new(
        action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
          workflow.name, nil, id: workflow.name, task_queue: workflow.owner
        ),
        spec: Temporalio::Client::Schedule::Spec.new(cron_expressions: [ schedule_def.cron ]),
        policy: Temporalio::Client::Schedule::Policy.new(overlap: schedule_overlap_policy(schedule_def))
      )
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

    # Deletes the static schedules schedules.yml no longer defines and returns
    # what it could not delete. Per-binding schedule triggers are never touched
    # here — they belong to ScheduleReconciler, and wiping them once wiped every
    # user's schedule trigger on deploy.
    def prune_schedules(keep:)
      failures = []
      with_client do |cl|
        cl.list_schedules.map(&:id).each do |id|
          next if id.start_with?(ScheduleReconciler::SCHEDULE_ID_PREFIX) || keep.include?(id)

          cl.schedule_handle(id).delete
        rescue Temporalio::Error::RPCError => e
          next if e.code == Temporalio::Error::RPCError::Code::NOT_FOUND

          failures << "#{id} (delete): #{e.message}"
        end
      end
      failures
    rescue StandardError => e
      failures << "listing schedules: #{e.class}: #{e.message}"
    end

    # Puts a dynamic, per-record schedule (e.g. a user's schedule trigger) in
    # the shape given, under a caller-supplied stable schedule_id: updated in
    # place when it exists, created when it does not. Fires the
    # ScheduledTriggerWorkflow on the given cron (optionally in a timezone).
    def upsert_binding_schedule(schedule_id:, cron:, input:, timezone: nil)
      workflow = TemporalWorkflowRegistry.workflows["scheduled_trigger_workflow"]
      return if workflow.nil?

      desired = Temporalio::Client::Schedule.new(
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

      with_client do |cl|
        cl.schedule_handle(schedule_id).update do |current|
          Temporalio::Client::Schedule::Update.new(schedule: desired.with(state: current.description.schedule.state))
        end
      rescue Temporalio::Error::RPCError => e
        raise unless e.code == Temporalio::Error::RPCError::Code::NOT_FOUND

        create_static_schedule(cl, schedule_id, desired)
      end
    end

    # Ids of the per-binding schedule triggers Temporal holds (ScheduleReconciler).
    def binding_schedule_ids
      with_client do |cl|
        cl.list_schedules.map(&:id).select { |id| id.start_with?(ScheduleReconciler::SCHEDULE_ID_PREFIX) }
      end || []
    end

    def delete_binding_schedule(schedule_id)
      with_client do |cl|
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

    # Activity concurrency: 80% of the process thread budget, so in-flight
    # activities stay under the DB pool bin/temporal_worker establishes from the
    # same setting. Floor of 1 — a misconfigured 0 would wedge the worker.
    def worker_activity_slots
      [ (Settings.temporal.worker_max_threads.to_i * 0.8).ceil, 1 ].max
    end

    private

    def create_static_schedule(client, id, schedule)
      client.create_schedule(id, schedule)
    rescue Temporalio::Error::ScheduleAlreadyRunningError
      # Another worker pod booting at the same moment created it first.
      Rails.logger.info("[Temporal] Schedule #{id} already exists")
    end

    def report_schedule_failures(failures)
      return if failures.empty?

      message = "Schedule sync left #{failures.size} schedule(s) unconverged: #{failures.join('; ')}"
      Rails.logger.error("[Temporal] #{message}")
      Sentry.capture_message(message, level: :error) if Sentry.initialized?
    end

    # Pre-resolve TemporalWorkflowRegistry lookups so workflows
    # never trigger autoloading inside the Temporal sandbox.
    def eager_load_workflow_registries!(workflow_classes)
      TemporalWorkflowRegistry.workflows
      workflow_classes.each(&:preload_activities!)
    end

    # How a call reaches Temporal: the configured server, unless a connection was
    # plugged in (see attr_writer :connection).
    def with_client(&block)
      return @connection.call(&block) if @connection
      return yield(client) if enabled?

      # A deployed environment with Temporal off runs no session and no workflow;
      # that is a misconfiguration to shout about, not a quiet skip.
      Rails.logger.public_send(Rails.env.local? ? :info : :error, "[Temporal] Skipped: Temporal is disabled")
      nil
    end
  end
end
