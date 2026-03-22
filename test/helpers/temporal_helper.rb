# frozen_string_literal: true

module TemporalHelper
  def mock_temporal_start
    TemporalService.stubs(:start_workflow).returns({
      ok: true,
      workflow_id: "temporal-wf-#{SecureRandom.hex(4)}",
      run_id: "temporal-run-#{SecureRandom.hex(4)}"
    })
  end

  def mock_workflow_execution_start
    TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns({
      ok: true,
      workflow_id: "workflow-execution-#{SecureRandom.hex(4)}",
      run_id: "workflow-run-#{SecureRandom.hex(4)}"
    })
  end
end
