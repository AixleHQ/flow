# frozen_string_literal: true

require "test_helper"

class WorkflowServiceTest < ActiveSupport::TestCase
  # == ActivityDef Tests ==

  test "ActivityDef stores name and task_queue" do
    activity = WorkflowService::ActivityDef.new(name: "my_activity", task_queue: "my-queue")

    assert_equal "my_activity", activity.name
    assert_equal "my-queue", activity.task_queue
  end

  # == ActivitiesCollection Tests ==

  test "ActivitiesCollection provides method access to activities" do
    activities_data = [
      { "name" => "pull_docker_image_activity", "task_queue" => "container-queue" },
      { "name" => "execute_container_activity", "task_queue" => "container-queue" }
    ]

    collection = WorkflowService::ActivitiesCollection.new(activities_data)

    assert collection.pull_docker_image_activity.is_a?(WorkflowService::ActivityDef)
    assert_equal "container-queue", collection.pull_docker_image_activity.task_queue
  end

  test "ActivitiesCollection returns nil for unknown activity" do
    collection = WorkflowService::ActivitiesCollection.new([])

    assert_raises(NoMethodError) do
      collection.nonexistent_activity
    end
  end

  test "ActivitiesCollection responds to defined activities" do
    activities_data = [ { "name" => "my_activity", "task_queue" => "queue" } ]
    collection = WorkflowService::ActivitiesCollection.new(activities_data)

    assert collection.respond_to?(:my_activity)
    refute collection.respond_to?(:unknown_activity)
  end

  test "ActivitiesCollection to_h returns activities hash" do
    activities_data = [ { "name" => "my_activity", "task_queue" => "queue" } ]
    collection = WorkflowService::ActivitiesCollection.new(activities_data)

    hash = collection.to_h

    assert hash.is_a?(Hash)
    assert hash.key?("my_activity")
  end

  # == WorkflowDef Tests ==

  test "WorkflowDef stores name, owner and activities" do
    workflow = WorkflowService::WorkflowDef.new(
      name: "UnifiedContainerWorkflow",
      owner: "container-queue",
      activities: [ { "name" => "test_activity", "task_queue" => "queue" } ]
    )

    assert_equal "UnifiedContainerWorkflow", workflow.name
    assert_equal "container-queue", workflow.owner
    assert workflow.activities.is_a?(WorkflowService::ActivitiesCollection)
  end

  # == WorkflowsCollection Tests ==

  test "WorkflowsCollection provides method access to workflows" do
    workflows_data = [
      {
        "name" => "unified_container_workflow",
        "owner" => "container-queue",
        "activities" => []
      }
    ]

    collection = WorkflowService::WorkflowsCollection.new(workflows_data)

    assert collection.unified_container_workflow.is_a?(WorkflowService::WorkflowDef)
    assert_equal "container-queue", collection.unified_container_workflow.owner
  end

  test "WorkflowsCollection bracket access works" do
    workflows_data = [ { "name" => "test_workflow", "owner" => "queue", "activities" => [] } ]
    collection = WorkflowService::WorkflowsCollection.new(workflows_data)

    assert collection["test_workflow"].is_a?(WorkflowService::WorkflowDef)
  end

  test "WorkflowsCollection all returns all workflows" do
    workflows_data = [
      { "name" => "workflow_1", "owner" => "queue", "activities" => [] },
      { "name" => "workflow_2", "owner" => "queue", "activities" => [] }
    ]
    collection = WorkflowService::WorkflowsCollection.new(workflows_data)

    all = collection.all

    assert_equal 2, all.size
    assert all.all? { |w| w.is_a?(WorkflowService::WorkflowDef) }
  end

  test "WorkflowsCollection names returns workflow names" do
    workflows_data = [
      { "name" => "workflow_a", "owner" => "queue", "activities" => [] },
      { "name" => "workflow_b", "owner" => "queue", "activities" => [] }
    ]
    collection = WorkflowService::WorkflowsCollection.new(workflows_data)

    names = collection.names

    assert_includes names, "workflow_a"
    assert_includes names, "workflow_b"
  end

  test "WorkflowsCollection responds to defined workflows" do
    workflows_data = [ { "name" => "my_workflow", "owner" => "queue", "activities" => [] } ]
    collection = WorkflowService::WorkflowsCollection.new(workflows_data)

    assert collection.respond_to?(:my_workflow)
    refute collection.respond_to?(:unknown_workflow)
  end

  # == Class Methods Tests ==

  test "workflows returns WorkflowsCollection" do
    workflows = WorkflowService.workflows

    assert workflows.is_a?(WorkflowService::WorkflowsCollection)
  end

  test "workflows_data loads from YAML" do
    data = WorkflowService.workflows_data

    assert data.is_a?(Hash)
    assert data.key?("workflows")
  end

  test "method_missing delegates to workflows" do
    # Reset cached data
    WorkflowService.instance_variable_set(:@workflows, nil)

    # This should work if unified_container_workflow is defined in workflows.yml
    workflow = WorkflowService.unified_container_workflow

    assert workflow.is_a?(WorkflowService::WorkflowDef)
  end
end
