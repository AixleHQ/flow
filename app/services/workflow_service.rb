# frozen_string_literal: true

# Workflow service to manage workflows and activities
class WorkflowService
  # Activity definition
  class ActivityDef
    attr_reader :name, :task_queue

    def initialize(name:, task_queue:)
      @name = name
      @task_queue = task_queue
    end
  end

  # Activities collection with method_missing for attribute access
  class ActivitiesCollection
    def initialize(activities_data)
      @activities = {}
      activities_data.each do |act|
        act_name = act["name"]
        @activities[act_name] = ActivityDef.new(
          name: act_name,
          task_queue: act["task_queue"]
        )
      end
    end

    def method_missing(method_name, *args, &block)
      activity = @activities[method_name.to_s]
      return activity if activity

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @activities.key?(method_name.to_s) || super
    end

    def to_h
      @activities
    end
  end

  # Workflow definition
  class WorkflowDef
    attr_reader :name, :owner, :activities

    def initialize(name:, owner:, activities:)
      @name = name
      @owner = owner
      @activities = ActivitiesCollection.new(activities)
    end
  end

  # Workflows collection with method_missing
  class WorkflowsCollection
    def initialize(workflows_data)
      @workflows = {}
      workflows_data.each do |wf|
        wf_name = wf["name"]
        @workflows[wf_name] = WorkflowDef.new(
          name: wf_name,
          owner: wf["owner"],
          activities: wf["activities"] || []
        )
      end
    end

    def method_missing(method_name, *args, &block)
      workflow = @workflows[method_name.to_s]
      return workflow if workflow

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @workflows.key?(method_name.to_s) || super
    end

    def all
      @workflows.values
    end

    def names
      @workflows.keys
    end

    def [](name)
      @workflows[name]
    end
  end

  class << self
    def workflows_data
      @workflows_data ||= load_workflows_yaml
    end

    def workflows
      @workflows ||= WorkflowsCollection.new(workflows_data["workflows"] || [])
    end

    # Shortcut access
    def method_missing(method_name, *args, &block)
      workflow = workflows.send(method_name)
      return workflow if workflow

      super
    rescue NoMethodError
      super
    end

    def respond_to_missing?(method_name, include_private = false)
      workflows.respond_to_missing?(method_name, include_private) || super
    end

    private

    def load_workflows_yaml
      yaml_path = Rails.root.join("app", "temporal", "workflows.yml")
      YAML.load_file(yaml_path)
    end
  end
end
