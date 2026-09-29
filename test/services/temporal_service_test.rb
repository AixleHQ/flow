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

  # == Payloads ==

  class Revivable
    def self.json_create(_hash) = new
  end

  test "a payload naming a json_class decodes as the hash it is, never as that class" do
    converter = TemporalService.data_converter.payload_converter
    payload = converter.to_payload({ "json_class" => Revivable.name, "session_id" => 7 })

    assert_equal({ "json_class" => Revivable.name, "session_id" => 7 }, converter.from_payload(payload))
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
    refute_predicate TemporalService, :enabled?
  end

  test "enabled? returns false when setting is nil" do
    Settings.temporal.stubs(:enabled).returns(nil)
    refute_predicate TemporalService, :enabled?
  end

  # == Activities & Workflows Loading ==

  test "activities returns descendants of Activities::Base" do
    activities = TemporalService.activities
    assert_kind_of Array, activities
    assert activities.all? { |a| a < Activities::Base }
  end

  test "workflows returns descendants of Workflows::Base" do
    workflows = TemporalService.workflows
    assert_kind_of Array, workflows
    assert workflows.all? { |w| w < Workflows::Base }
  end

  # == Workflow ID ==

  # Object#hash is seeded per process, so an id derived from the input never
  # deduplicated anything across pods.
  test "a start without an explicit workflow id is refused" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    assert_raises(ArgumentError) { TemporalService.start_workflow(workflow, { test: true }) }
    assert_raises(ArgumentError) { TemporalService.execute_workflow(workflow, { test: true }) }
  end

  # == Start Workflow Tests ==

  test "start_workflow returns error when result is nil" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    # start_local returns nil (stubbed)
    result = TemporalService.start_workflow(workflow, { test: true }, id: "test-wf")

    refute result[:ok]
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

    assert result[:ok]
    assert_equal "custom-id", result[:workflow_id]
    assert_equal "run-123", result[:run_id]
  end

  test "start_workflow handles Temporal errors" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Connection refused")
    )

    result = TemporalService.start_workflow(workflow, { test: true }, id: "test-wf")

    refute result[:ok]
    assert_match(/Connection refused/, result[:error])
  end

  # == Execute Workflow Tests ==

  test "execute_workflow returns nil when disabled" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")
    Settings.temporal.stubs(:enabled).returns("false")

    # start_local returns nil (stubbed)
    result = TemporalService.execute_workflow(workflow, { test: true }, id: "test-wf")

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

    result = TemporalService.execute_workflow(workflow, { test: true }, id: "test-wf")

    assert_equal expected_result, result
  end

  test "execute_workflow raises on Temporal error" do
    workflow = OpenStruct.new(name: "TestWorkflow", owner: "test-queue")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Execution failed")
    )

    assert_raises(Temporalio::Error) do
      TemporalService.execute_workflow(workflow, { test: true }, id: "test-wf")
    end
  end

  # == Send Signal Tests ==

  test "send_signal returns error when temporal disabled" do
    Settings.temporal.stubs(:enabled).returns("false")

    result = TemporalService.send_signal("workflow-123", "container_finished")

    refute result[:ok]
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

    assert result[:ok]
  end

  test "send_signal handles temporal errors" do
    Settings.temporal.stubs(:enabled).returns("true")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Connection failed")
    )

    result = TemporalService.send_signal("workflow-123", "test_signal")

    refute result[:ok]
    assert_match(/Connection failed/, result[:error])
  end

  # == Execution state ==

  def describing(workflow_id)
    handle = mock("handle")
    client = mock("client")
    client.stubs(:workflow_handle).with(workflow_id).returns(handle)
    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(OpenStruct.new(client: client))
    handle
  end

  test "execution_state tells running from closed" do
    Settings.temporal.stubs(:enabled).returns("true")
    handle = describing("workflow-execution-1")

    handle.stubs(:describe).returns(OpenStruct.new(status: Temporalio::Client::WorkflowExecutionStatus::RUNNING))
    assert_equal :running, TemporalService.execution_state("workflow-execution-1")

    handle.stubs(:describe).returns(OpenStruct.new(status: Temporalio::Client::WorkflowExecutionStatus::TERMINATED))
    assert_equal :closed, TemporalService.execution_state("workflow-execution-1")
  end

  test "execution_state reports an execution Temporal has no record of as not_found" do
    Settings.temporal.stubs(:enabled).returns("true")
    describing("workflow-execution-1").stubs(:describe).raises(
      Temporalio::Error::RPCError.new("not found", code: Temporalio::Error::RPCError::Code::NOT_FOUND, raw_grpc_status: nil)
    )

    assert_equal :not_found, TemporalService.execution_state("workflow-execution-1")
  end

  test "execution_state is unknown when Temporal cannot be asked" do
    Settings.temporal.stubs(:enabled).returns("true")
    describing("workflow-execution-1").stubs(:describe).raises(
      Temporalio::Error::RPCError.new("down", code: Temporalio::Error::RPCError::Code::UNAVAILABLE, raw_grpc_status: nil)
    )

    assert_equal :unknown, TemporalService.execution_state("workflow-execution-1")

    Settings.temporal.stubs(:enabled).returns("false")
    assert_equal :unknown, TemporalService.execution_state("workflow-execution-1")
  end

  # == Cancel Workflow Tests ==

  test "cancel_workflow returns error when temporal disabled" do
    Settings.temporal.stubs(:enabled).returns("false")

    result = TemporalService.cancel_workflow("workflow-123")

    refute result[:ok]
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

    assert result[:ok]
  end

  test "cancel_workflow handles temporal errors" do
    Settings.temporal.stubs(:enabled).returns("true")

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).raises(
      Temporalio::Error.new("Workflow not found")
    )

    result = TemporalService.cancel_workflow("workflow-123")

    refute result[:ok]
    assert_match(/Workflow not found/, result[:error])
  end

  # == Schedule Tests ==

  test "schedule_definitions loads from yaml file" do
    mock_schedules = { "schedules" => [ { "workflow" => "test", "cron" => "0 * * * *" } ] }
    YAML.stubs(:load_file).returns(mock_schedules)

    definitions = TemporalService.schedule_definitions

    assert_kind_of Array, definitions
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

  test "prune_schedules deletes the static schedules that are no longer defined" do
    mock_handle = mock("handle")
    mock_handle.expects(:delete)

    mock_client = mock("client")
    mock_client.expects(:list_schedules).returns([ OpenStruct.new(id: "gone"), OpenStruct.new(id: "kept") ])
    mock_client.expects(:schedule_handle).with("gone").returns(mock_handle)
    mock_client.expects(:schedule_handle).with("kept").never

    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(
      OpenStruct.new(client: mock_client)
    )

    assert_empty TemporalService.prune_schedules(keep: [ "kept" ])
  end

  # == Schedule sync converges ==

  def schedule_env(client)
    Temporalio::Testing::WorkflowEnvironment.stubs(:start_local).yields(OpenStruct.new(client: client))
  end

  def not_found
    Temporalio::Error::RPCError.new("not found", code: Temporalio::Error::RPCError::Code::NOT_FOUND, raw_grpc_status: nil)
  end

  def with_definitions(*names)
    workflows = names.to_h { |n| [ n, OpenStruct.new(name: n.camelize, owner: "q") ] }
    TemporalWorkflowRegistry.stubs(:workflows).returns(workflows)
    TemporalService.stubs(:schedule_definitions).returns(
      names.map { |n| OpenStruct.new(workflow: n, cron: "0 * * * *", enabled: true) }
    )
  end

  test "sync_schedules updates existing schedules in place and never deletes a defined one" do
    with_definitions("alpha")
    handle = mock("handle")
    handle.expects(:update).once
    handle.expects(:delete).never
    client = mock("client")
    client.stubs(:schedule_handle).with("Alpha").returns(handle)
    client.expects(:list_schedules).returns([ OpenStruct.new(id: "Alpha") ])
    client.expects(:create_schedule).never
    schedule_env(client)
    ScheduleReconciler.expects(:reconcile_all).once

    assert_empty TemporalService.sync_schedules
  end

  test "sync_schedules creates a schedule Temporal does not have" do
    with_definitions("alpha")
    handle = mock("handle")
    handle.stubs(:update).raises(not_found)
    client = mock("client")
    client.stubs(:schedule_handle).with("Alpha").returns(handle)
    client.expects(:create_schedule).with("Alpha", instance_of(Temporalio::Client::Schedule)).once
    client.stubs(:list_schedules).returns([])
    schedule_env(client)
    ScheduleReconciler.stubs(:reconcile_all)

    assert_empty TemporalService.sync_schedules
  end

  test "upsert_binding_schedule updates in place and creates only when missing" do
    TemporalWorkflowRegistry.stubs(:workflows).returns(
      { "scheduled_trigger_workflow" => OpenStruct.new(name: "ScheduledTriggerWorkflow", owner: "q") }
    )
    existing = mock("existing")
    existing.expects(:update).once
    missing = mock("missing")
    missing.stubs(:update).raises(not_found)
    client = mock("client")
    client.stubs(:schedule_handle).with("schedule-trigger-1").returns(existing)
    client.stubs(:schedule_handle).with("schedule-trigger-2").returns(missing)
    client.expects(:create_schedule).with("schedule-trigger-2", instance_of(Temporalio::Client::Schedule)).once
    schedule_env(client)

    TemporalService.upsert_binding_schedule(schedule_id: "schedule-trigger-1", cron: "0 9 * * *", input: {})
    TemporalService.upsert_binding_schedule(schedule_id: "schedule-trigger-2", cron: "0 9 * * *", input: {})
  end

  # One failure must not abort the loop and leave every later schedule missing.
  test "one failing schedule does not stop the others, and is reported" do
    with_definitions("alpha", "beta")
    broken = mock("broken")
    broken.stubs(:update).raises(RuntimeError, "boom")
    healthy = mock("healthy")
    healthy.expects(:update).once
    client = mock("client")
    client.stubs(:schedule_handle).with("Alpha").returns(broken)
    client.stubs(:schedule_handle).with("Beta").returns(healthy)
    client.stubs(:list_schedules).returns([ OpenStruct.new(id: "Alpha"), OpenStruct.new(id: "Beta") ])
    schedule_env(client)
    ScheduleReconciler.expects(:reconcile_all).once

    failures = TemporalService.sync_schedules

    assert_equal 1, failures.size
    assert_match(/alpha: RuntimeError: boom/, failures.first)
  end

  test "sync_schedules prunes undefined static schedules but preserves per-binding schedule triggers" do
    with_definitions("alpha")
    handle = mock("handle")
    handle.stubs(:update)
    stale = mock("stale")
    stale.expects(:delete).once
    client = mock("client")
    client.stubs(:schedule_handle).with("Alpha").returns(handle)
    client.stubs(:schedule_handle).with("stale_static_workflow").returns(stale)
    client.expects(:schedule_handle).with("schedule-trigger-3").never
    client.stubs(:list_schedules).returns(
      [ OpenStruct.new(id: "Alpha"), OpenStruct.new(id: "stale_static_workflow"), OpenStruct.new(id: "schedule-trigger-3") ]
    )
    schedule_env(client)
    ScheduleReconciler.stubs(:reconcile_all)

    assert_empty TemporalService.sync_schedules
  end
end
