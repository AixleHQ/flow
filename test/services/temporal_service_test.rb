# frozen_string_literal: true

require "test_helper"

class TemporalServiceTest < ActiveSupport::TestCase
  setup do
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    # Clear memoized values
    TemporalService.instance_variable_set(:@client, nil)
    TemporalService.instance_variable_set(:@worker, nil)
    TemporalService.instance_variable_set(:@address, nil)
    TemporalService.instance_variable_set(:@namespace, nil)
    TemporalService.instance_variable_set(:@activities, nil)
    TemporalService.instance_variable_set(:@workflows, nil)
    TemporalService.instance_variable_set(:@schedule_definitions, nil)

    # Stub local environment to avoid hanging
    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local)
  end

  # == Configuration Tests ==

  test "address combines host and port from settings" do
    Settings.temporal.stubs(:host).returns("localhost")
    Settings.temporal.stubs(:port).returns(7233)

    assert_equal "localhost:7233", TemporalService.address
  end

  test "namespace returns from settings" do
    Settings.temporal.stubs(:namespace).returns("test-namespace")

    assert_equal "test-namespace", TemporalService.namespace
  end

  test "enabled? returns true when setting is true" do
    Settings.temporal.stubs(:enabled).returns("true")
    assert TemporalService.enabled?
  end

  test "enabled? returns false when setting is false" do
    Settings.temporal.stubs(:enabled).returns("false")
    refute TemporalService.enabled?
  end

  test "enabled? returns false when setting is nil" do
    Settings.temporal.stubs(:enabled).returns(nil)
    refute TemporalService.enabled?
  end

  # == Activities & Workflows Loading ==

  test "activities returns descendants of Activities::Base" do
    activities = TemporalService.activities
    assert activities.is_a?(Array)
    assert activities.all? { |a| a < Activities::Base }
  end

  test "workflows returns descendants of Workflows::Base" do
    workflows = TemporalService.workflows
    assert workflows.is_a?(Array)
    assert workflows.all? { |w| w < Workflows::Base }
  end

  # == Workflow ID Generation ==

  test "workflow_id generates deterministic id from workflow and input" do
    workflow = OpenStruct.new(name: "TestWorkflow")
    input = { key: "value" }

    id1 = TemporalService.workflow_id(workflow, input)
    id2 = TemporalService.workflow_id(workflow, input)

    assert_equal id1, id2
    assert id1.start_with?("TestWorkflow-")
  end

  test "workflow_id generates different ids for different inputs" do
    workflow = OpenStruct.new(name: "TestWorkflow")

    id1 = TemporalService.workflow_id(workflow, { a: 1 })
    id2 = TemporalService.workflow_id(workflow, { b: 2 })

    refute_equal id1, id2
  end

  # == Start Workflow Tests ==

  test "start_workflow returns error when result is nil" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    # start_local returns nil (stubbed)
    result = TemporalService.start_workflow(workflow, { test: true })

    assert_equal false, result[:ok]
    assert_equal "Temporal is disabled", result[:error]
  end

  test "start_workflow uses custom id and timeout" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")
    mock_handle = OpenStruct.new(id: "custom-id", run_id: "run-123")

    mock_client = mock("client")
    mock_client.expects(:start_workflow).with(
      "TestWorkflow",
      { test: true },
      has_entries(id: "custom-id", execution_timeout: 3600)
    ).returns(mock_handle)

    # start_local yields env, then the code calls env.client
    mock_env = OpenStruct.new(client: mock_client)

    Temporalio::Testing::WorkflowEnvironment.unstub(:start_local)
    Temporalio::Testing::WorkflowEnvironment.expects(:start_local).yields(mock_env).returns(mock_handle)

    result = TemporalService.start_workflow(workflow, { test: true }, id: "custom-id", execution_timeout: 3600)

    assert_equal true, result[:ok]
    assert_equal "custom-id", result[:workflow_id]
    assert_equal "run-123", result[:run_id]
  end

  test "start_workflow handles Temporal errors" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Connection refused")
    )

    result = TemporalService.start_workflow(workflow, { test: true })

    assert_equal false, result[:ok]
    assert_match(/Connection refused/, result[:error])
  end

  # == Execute Workflow Tests ==

  test "execute_workflow returns nil when disabled" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")
    Settings.temporal.stubs(:enabled).returns("false")

    # start_local returns nil (stubbed)
    result = TemporalService.execute_workflow(workflow, { test: true })

    assert_nil result
  end

  test "execute_workflow returns result on success" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")
    expected_result = { status: "completed", data: 42 }

    mock_client = mock("client")
    mock_client.expects(:execute_workflow).returns(expected_result)
    mock_env = OpenStruct.new(client: mock_client)

    Temporalio::Testing::WorkflowEnvironment.unstub(:start_local)
    Temporalio::Testing::WorkflowEnvironment.expects(:start_local).yields(mock_env).returns(expected_result)

    result = TemporalService.execute_workflow(workflow, { test: true })

    assert_equal expected_result, result
  end

  test "execute_workflow raises on Temporal error" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Execution failed")
    )

    assert_raises(Temporalio::Error) do
      TemporalService.execute_workflow(workflow, { test: true })
    end
  end

  # == Send Signal Tests ==

  test "send_signal returns error when temporal disabled" do
    Settings.temporal.stubs(:enabled).returns("false")

    result = TemporalService.send_signal("workflow-123", "container_finished")

    assert_equal false, result[:ok]
    assert_equal "Temporal is disabled", result[:error]
  end

  test "send_signal sends signal successfully" do
    Settings.temporal.stubs(:enabled).returns("true")

    mock_handle = mock("handle")
    mock_handle.expects(:signal).with("container_finished", nil)

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock("client").tap { |c|
        c.expects(:workflow_handle).with("workflow-123").returns(mock_handle)
      })
    )

    result = TemporalService.send_signal("workflow-123", "container_finished")

    assert_equal true, result[:ok]
  end

  test "send_signal handles temporal errors" do
    Settings.temporal.stubs(:enabled).returns("true")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Connection failed")
    )

    result = TemporalService.send_signal("workflow-123", "test_signal")

    assert_equal false, result[:ok]
    assert_match(/Connection failed/, result[:error])
  end

  # == Cancel Workflow Tests ==

  test "cancel_workflow returns error when temporal disabled" do
    Settings.temporal.stubs(:enabled).returns("false")

    result = TemporalService.cancel_workflow("workflow-123")

    assert_equal false, result[:ok]
    assert_equal "Temporal is disabled", result[:error]
  end

  test "cancel_workflow cancels successfully" do
    Settings.temporal.stubs(:enabled).returns("true")

    mock_handle = mock("handle")
    mock_handle.expects(:cancel)

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock("client").tap { |c|
        c.expects(:workflow_handle).with("workflow-123").returns(mock_handle)
      })
    )

    result = TemporalService.cancel_workflow("workflow-123")

    assert_equal true, result[:ok]
  end

  test "cancel_workflow handles temporal errors" do
    Settings.temporal.stubs(:enabled).returns("true")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Workflow not found")
    )

    result = TemporalService.cancel_workflow("workflow-123")

    assert_equal false, result[:ok]
    assert_match(/Workflow not found/, result[:error])
  end

  # == Schedule Tests ==

  test "schedule_definitions loads from yaml file" do
    mock_schedules = { "schedules" => [ { "workflow" => "test", "cron" => "0 * * * *" } ] }
    YAML.stubs(:load_file).returns(mock_schedules)

    definitions = TemporalService.schedule_definitions

    assert definitions.is_a?(Array)
  end

  test "create_schedule creates schedule when enabled" do
    schedule_def = OpenStruct.new(workflow: "agent_container_workflow", cron: "0 * * * *", enabled: true)
    workflow = OpenStruct.new(name: "AgentContainerWorkflow", owner: "web")

    TemporalWorkflowRegistry.stubs(:workflows).returns({ "agent_container_workflow" => workflow })

    mock_client = mock("client")
    mock_client.expects(:create_schedule).with("AgentContainerWorkflow", anything)

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock_client)
    )

    TemporalService.create_schedule(schedule_def)
  end

  test "create_schedule skips when disabled" do
    schedule_def = OpenStruct.new(workflow: "test", cron: "0 * * * *", enabled: false)
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    TemporalWorkflowRegistry.stubs(:workflows).returns({ "test" => workflow })

    mock_client = mock("client")
    mock_client.expects(:create_schedule).never

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock_client)
    )

    TemporalService.create_schedule(schedule_def)
  end

  test "delete_schedules deletes all schedules" do
    mock_schedule1 = OpenStruct.new(id: "schedule-1")
    mock_schedule2 = OpenStruct.new(id: "schedule-2")

    mock_handle1 = mock("handle1")
    mock_handle1.expects(:delete)
    mock_handle2 = mock("handle2")
    mock_handle2.expects(:delete)

    mock_client = mock("client")
    mock_client.expects(:list_schedules).returns([ mock_schedule1, mock_schedule2 ])
    mock_client.expects(:schedule_handle).with("schedule-1").returns(mock_handle1)
    mock_client.expects(:schedule_handle).with("schedule-2").returns(mock_handle2)

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock_client)
    )

    TemporalService.delete_schedules
  end

  test "delete_schedule deletes specific schedule" do
    schedule_def = OpenStruct.new(workflow: "test")
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    TemporalWorkflowRegistry.stubs(:workflows).returns({ "test" => workflow })

    mock_handle = mock("handle")
    mock_handle.expects(:delete)

    mock_client = mock("client")
    mock_client.expects(:schedule_handle).with("TestWorkflow").returns(mock_handle)

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock_client)
    )

    TemporalService.delete_schedule(schedule_def)
  end

  test "delete_schedule deletes schedule successfully" do
    schedule_def = OpenStruct.new(workflow: "test")
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    TemporalWorkflowRegistry.stubs(:workflows).returns({ "test" => workflow })

    mock_handle = mock("handle")
    mock_handle.expects(:delete)

    mock_client = mock("client")
    mock_client.expects(:schedule_handle).with("TestWorkflow").returns(mock_handle)

    mock_env = OpenStruct.new(client: mock_client)

    Temporalio::Testing::WorkflowEnvironment.unstub(:start_local)
    Temporalio::Testing::WorkflowEnvironment.expects(:start_local).yields(mock_env)

    TemporalService.delete_schedule(schedule_def)
  end

  test "sync_schedules deletes and recreates schedules" do
    TemporalService.expects(:delete_schedules).once
    TemporalService.stubs(:schedule_definitions).returns([
      OpenStruct.new(workflow: "test", cron: "0 * * * *", enabled: true)
    ])
    TemporalService.expects(:create_schedule).once

    TemporalService.sync_schedules
  end
end
