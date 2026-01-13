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
      @worker ||= Temporalio::Worker.new(
        client: client,
        task_queue: Settings.temporal.task_queue,
        activities: activities,
        workflows: workflows,
      )
    end

    def address
      @address ||= "#{Settings.temporal.host}:#{Settings.temporal.port}"
    end

    def namespace
      @namespace ||= Settings.temporal.namespace
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
      @schedule_definitions ||= Hashie::Mash.new(YAML.load_file(Rails.root.join("app/temporal/schedules.yml"))).schedules
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
      id = workflow_id(workflow, input)
      handle = with_test_environment_handling do |cl|
        cl.start_workflow(workflow.name, input, id: id, task_queue: workflow.owner)
      end

      return { ok: false, error: "Temporal is disabled" } if handle.nil?

      Rails.logger.info("[Temporal] ✅ Workflow #{id} queued: #{handle.id}")

      { ok: true, workflow_id: handle.id, run_id: handle.run_id, handle: handle }
    rescue Temporalio::Error => e
      { ok: false, error: e.message }
    end

    def execute_workflow(workflow, input, options = {})
      id = workflow_id(workflow, input)

      result = with_test_environment_handling do |cl|
        cl.execute_workflow(workflow.name, input, id: id, task_queue: workflow.owner)
      end

      return nil if result.nil? && !enabled?

      Rails.logger.info("[Temporal] ✅ Workflow #{id} completed: #{result}")
      result
    rescue Temporalio::Error => e
      Rails.logger.info("[Temporal] ❌ Workflow #{id} execution failed: #{e.message}")
      raise
    end

    def create_schedule(schedule_def)
      workflow = WorkflowService.workflows[schedule_def.workflow]
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
              overlap: Temporalio::Client::Schedule::OverlapPolicy::BUFFER_ONE
            ),
          )
        ) if schedule_def.enabled
      end
    end

    def delete_schedules
      with_test_environment_handling do |cl|
        ids = cl.list_schedules.map { |x| x.id }
        ids.each { |id| cl.schedule_handle(id).delete }
      end
    end

    def delete_schedule(schedule_def)
      workflow = WorkflowService.workflows[schedule_def.workflow]
      with_test_environment_handling do |cl|
        cl.schedule_handle(workflow.name).delete
      end
    rescue Temporalio::Error::RPCError => e
    end

    def enabled?
      Settings.temporal.enabled.to_s == "true"
    end

    private

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
