# frozen_string_literal: true

require "test_helper"

class TemporalWorkflowRegistryTest < ActiveSupport::TestCase
  # == ActivityDef Tests ==

  test "ActivityDef stores name and task_queue" do
    activity = TemporalWorkflowRegistry::ActivityDef.new(name: "my_activity", task_queue: "my-queue")

    assert_equal "my_activity", activity.name
    assert_equal "my-queue", activity.task_queue
  end

  # == ActivitiesCollection Tests ==

  test "ActivitiesCollection provides method access to activities" do
    activities_data = [
      { "name" => "pull_agent_image_activity", "task_queue" => "container-queue" },
      { "name" => "execute_agent_container_activity", "task_queue" => "container-queue" }
    ]

    collection = TemporalWorkflowRegistry::ActivitiesCollection.new(activities_data)

    assert_kind_of TemporalWorkflowRegistry::ActivityDef, collection.pull_agent_image_activity
    assert_equal "container-queue", collection.pull_agent_image_activity.task_queue
  end

  test "ActivitiesCollection returns nil for unknown activity" do
    collection = TemporalWorkflowRegistry::ActivitiesCollection.new([])

    assert_raises(NoMethodError) do
      collection.nonexistent_activity
    end
  end

  test "ActivitiesCollection responds to defined activities" do
    activities_data = [ { "name" => "my_activity", "task_queue" => "queue" } ]
    collection = TemporalWorkflowRegistry::ActivitiesCollection.new(activities_data)

    assert_respond_to collection, :my_activity
    refute_respond_to collection, :unknown_activity
  end

  test "ActivitiesCollection to_h returns activities hash" do
    activities_data = [ { "name" => "my_activity", "task_queue" => "queue" } ]
    collection = TemporalWorkflowRegistry::ActivitiesCollection.new(activities_data)

    hash = collection.to_h

    assert_kind_of Hash, hash
    assert hash.key?("my_activity")
  end

  # == WorkflowDef Tests ==

  test "WorkflowDef stores name, owner and activities" do
    workflow = TemporalWorkflowRegistry::WorkflowDef.new(
      name: "AgentContainerWorkflow",
      owner: "web",
      activities: [ { "name" => "test_activity", "task_queue" => "queue" } ]
    )

    assert_equal "AgentContainerWorkflow", workflow.name
    assert_equal "web", workflow.owner
    assert_kind_of TemporalWorkflowRegistry::ActivitiesCollection, workflow.activities
  end

  # == WorkflowsCollection Tests ==

  test "WorkflowsCollection provides method access to workflows" do
    workflows_data = [
      {
        "name" => "container_workflow",
        "owner" => "web",
        "activities" => []
      }
    ]

    collection = TemporalWorkflowRegistry::WorkflowsCollection.new(workflows_data)

    assert_kind_of TemporalWorkflowRegistry::WorkflowDef, collection.container_workflow
    assert_equal "web", collection.container_workflow.owner
  end

  test "WorkflowsCollection bracket access works" do
    workflows_data = [ { "name" => "test_workflow", "owner" => "queue", "activities" => [] } ]
    collection = TemporalWorkflowRegistry::WorkflowsCollection.new(workflows_data)

    assert_kind_of TemporalWorkflowRegistry::WorkflowDef, collection["test_workflow"]
  end

  test "WorkflowsCollection all returns all workflows" do
    workflows_data = [
      { "name" => "workflow_1", "owner" => "queue", "activities" => [] },
      { "name" => "workflow_2", "owner" => "queue", "activities" => [] }
    ]
    collection = TemporalWorkflowRegistry::WorkflowsCollection.new(workflows_data)

    all = collection.all

    assert_equal 2, all.size
    assert all.all? { |w| w.is_a?(TemporalWorkflowRegistry::WorkflowDef) }
  end

  test "WorkflowsCollection names returns workflow names" do
    workflows_data = [
      { "name" => "workflow_a", "owner" => "queue", "activities" => [] },
      { "name" => "workflow_b", "owner" => "queue", "activities" => [] }
    ]
    collection = TemporalWorkflowRegistry::WorkflowsCollection.new(workflows_data)

    names = collection.names

    assert_includes names, "workflow_a"
    assert_includes names, "workflow_b"
  end

  test "WorkflowsCollection responds to defined workflows" do
    workflows_data = [ { "name" => "my_workflow", "owner" => "queue", "activities" => [] } ]
    collection = TemporalWorkflowRegistry::WorkflowsCollection.new(workflows_data)

    assert_respond_to collection, :my_workflow
    refute_respond_to collection, :unknown_workflow
  end

  # == Class Methods Tests ==

  test "workflows returns WorkflowsCollection" do
    workflows = TemporalWorkflowRegistry.workflows

    assert_kind_of TemporalWorkflowRegistry::WorkflowsCollection, workflows
  end

  test "workflows_data loads from YAML" do
    data = TemporalWorkflowRegistry.workflows_data

    assert_kind_of Hash, data
    assert data.key?("workflows")
  end

  test "method_missing delegates to workflows" do
    TemporalWorkflowRegistry.instance_variable_set(:@workflows, nil)
    TemporalWorkflowRegistry.instance_variable_set(:@workflows_data, nil)

    workflow = TemporalWorkflowRegistry.container_workflow

    assert_kind_of TemporalWorkflowRegistry::WorkflowDef, workflow
  end

  # == start_workflow_execution ==

  test "start_workflow_execution starts under a stable id, scoped to reuse only over a failed/cancelled/timed-out prior execution" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    workflow = create(:workflow, scope: project)
    run = create(:workflow_run, project: project, workflow: workflow, user: user)

    TemporalService.expects(:start_workflow).with(
      TemporalWorkflowRegistry.workflow_execution_workflow,
      { workflow_run_id: run.id },
      id: "workflow-execution-#{run.id}",
      execution_timeout: 86_400,
      id_reuse_policy: Temporalio::WorkflowIDReusePolicy::ALLOW_DUPLICATE_FAILED_ONLY
    ).returns(ok: true)

    result = TemporalWorkflowRegistry.start_workflow_execution(run)

    assert result[:ok]
  end
end
