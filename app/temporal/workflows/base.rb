require "temporalio/workflow"

class Workflows::Base < Temporalio::Workflow::Definition
  class << self
    def inherited(subclass)
      super
      workflow_name = subclass.name.split("::")[1..-1].join("_").underscore
      subclass.workflow_name(workflow_name) unless subclass.instance_variable_get(:@workflow_name)
    end

    # Pre-resolve activities at class level (before Temporal sandbox).
    # Called from TemporalService.eager_load_workflow_registries!
    def preload_activities!
      wf_name = instance_variable_get(:@workflow_name)
      return unless wf_name

      registry_entry = TemporalWorkflowRegistry.send(wf_name)
      @_preloaded_activities = registry_entry&.activities
    rescue StandardError => e
      Rails.logger.warn("[Temporal] Failed to preload activities for #{wf_name}: #{e.message}")
    end

    attr_reader :_preloaded_activities
  end

  def name
    self.class.instance_variable_get(:@workflow_name)
  end

  def execute(input = nil)
    hashie_input = input.is_a?(Hash) ? Hashie::Mash.new(input) : input
    run(hashie_input)
  end

  def execute_activity(activity, *args, **kwargs)
    Temporalio::Workflow.execute_activity(
      activity.name,
      *args,
      retry_policy: default_retry_policy,
      task_queue: activity.task_queue,
      start_to_close_timeout: 3600,
      **kwargs
    )
  end

  private

  def activities
    self.class._preloaded_activities
  end

  def extract_error_message(activity_error)
    cause = activity_error.cause
    cause ? cause.message : activity_error.message
  end

  def default_retry_policy
    Temporalio::RetryPolicy.new(
      max_attempts: 5,
      initial_interval: 5,
      backoff_coefficient: 3.0
    )
  end
end
