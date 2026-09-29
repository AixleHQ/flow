# frozen_string_literal: true

require "fileutils"
require "temporalio/testing"
require "temporalio/worker"
require "temporalio/worker/workflow_replayer"

# Recorded workflow histories. A deploy replays every open execution's history
# against the new workflow code, and code that would issue different commands
# for it wedges that execution — so every history under DIR must replay on the
# current code (test/temporal/workflows/history_replay_test.rb). How and when
# to record: docs/architecture/temporal-versioning.md.
module TemporalHistories
  DIR = Rails.root.join("test/fixtures/files/temporal_histories")

  # drive: called with a Driver after the start and before the result is read,
  # while the test server's clock stands still — which is what lets it deliver a
  # signal to a workflow parked on a timer. outcome: how the execution must end,
  # so a scenario cannot silently record something other than what it names.
  Scenario = Data.define(:name, :workflow, :input, :activities, :drive, :outcome) do
    def initialize(name:, workflow:, input:, activities:, drive: nil, outcome: :completed)
      super
    end

    def workflow_type = Temporalio::Workflow::Definition::Info.from_class(workflow).name
    def path(label) = DIR.join(workflow_type, name, "#{label}.json")
    def recorded = Dir[DIR.join(workflow_type, name, "*.json")]
  end

  class Driver
    POLL = 0.02
    WAIT = 30
    CLOSED = %i[
      EVENT_TYPE_WORKFLOW_EXECUTION_COMPLETED EVENT_TYPE_WORKFLOW_EXECUTION_FAILED
      EVENT_TYPE_WORKFLOW_EXECUTION_CANCELED EVENT_TYPE_WORKFLOW_EXECUTION_TERMINATED
      EVENT_TYPE_WORKFLOW_EXECUTION_TIMED_OUT
    ].freeze

    def initialize(handle)
      @handle = handle
    end

    # Blocks until the execution has started its count-th timer: the workflow
    # is now parked waiting, not still reacting to what came before.
    def await_timer(count = 1)
      await("timer ##{count}") { |events| timers(events) >= count }
    end

    # For a scenario that one version of the code finishes without waiting:
    # true once the count-th timer has started, false if the execution closed first.
    def await_timer_unless_closed(count = 1)
      events = await("timer ##{count} or the close") { |seen| timers(seen) >= count || closed?(seen) }
      !closed?(events)
    end

    def signal(name, *args) = @handle.signal(name.to_s, *args)
    def cancel = @handle.cancel

    private

    def timers(events) = events.count { |event| event.event_type == :EVENT_TYPE_TIMER_STARTED }
    def closed?(events) = events.any? { |event| CLOSED.include?(event.event_type) }

    def await(what)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT
      loop do
        events = @handle.fetch_history.events
        return events if yield(events)
        raise "#{@handle.id}: gave up waiting for #{what}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        Kernel.sleep(POLL)
      end
    end
  end

  class << self
    def scenarios = TemporalHistoryScenarios.all

    def fixtures = Dir[DIR.join("**/*.json")]

    def record(scenario, label:)
      with_registered_activities([ scenario.workflow ]) do
        env = Temporalio::Testing::WorkflowEnvironment.start_time_skipping(data_converter: TemporalService.data_converter)
        queue = Settings.temporal.task_queue.to_s
        worker = Temporalio::Worker.new(
          client: env.client, task_queue: queue, workflows: [ scenario.workflow ],
          activities: scenario.activities.map { |name, handler| scripted_activity(name, handler) },
          workflow_failure_exception_types: [ Exception ]
        )
        worker.run do
          handle = env.client.start_workflow(scenario.workflow, scenario.input,
            id: "history-#{scenario.workflow_type}-#{scenario.name}", task_queue: queue)
          scenario.drive&.call(Driver.new(handle))
          outcome = outcome_of(handle)
          raise "#{scenario.name} ended #{outcome}, expected #{scenario.outcome}" unless outcome == scenario.outcome

          path = scenario.path(label)
          FileUtils.mkdir_p(path.dirname)
          File.write(path, "#{handle.fetch_history.to_history_json}\n")
          path
        end
      ensure
        env&.shutdown
      end
    end

    # Replays with the production workflow classes and the activity names the
    # registry gives them, as the worker would.
    def replay(paths)
      workflows = production_workflows
      with_registered_activities(workflows) do
        replayer = Temporalio::Worker::WorkflowReplayer.new(workflows: workflows)
        histories = paths.map { |path| Temporalio::WorkflowHistory.from_history_json(File.read(path)) }
        paths.zip(replayer.replay_workflows(histories))
      end
    end

    private

    def outcome_of(handle)
      handle.result
      :completed
    rescue Temporalio::Error::WorkflowFailedError => e
      Temporalio::Error.canceled?(e.cause) ? :cancelled : :failed
    end

    # handler: ->(input, call_index) { result }; call_index counts this
    # activity's earlier calls, retries included.
    def scripted_activity(name, handler)
      calls = 0
      Temporalio::Activity::Definition::Info.new(name: name) do |input = nil|
        index = calls
        calls += 1
        handler.call(input, index)
      end
    end

    def production_workflows
      TemporalService.workflows.select do |workflow|
        workflow.name&.start_with?("Workflows::") &&
          Rails.root.join("app/temporal/workflows", "#{workflow.name.demodulize.underscore}.rb").exist?
      end
    end

    def with_registered_activities(workflows)
      saved = workflows.to_h { |workflow| [ workflow, workflow.instance_variable_get(:@_preloaded_activities) ] }
      workflows.each(&:preload_activities!)
      yield
    ensure
      saved&.each { |workflow, activities| workflow.instance_variable_set(:@_preloaded_activities, activities) }
    end
  end
end
