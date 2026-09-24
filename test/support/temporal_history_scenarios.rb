# frozen_string_literal: true

# The executions TemporalHistories records: one per command path worth
# guarding, with activities scripted to the shapes the real ones return.
module TemporalHistoryScenarios
  RUN_ID = 101
  SESSION_MANIFEST = {
    "pull_image" => { "timeout" => 600 },
    "create_container" => { "timeout" => 300 },
    "start_container" => { "timeout" => 300 },
    "exec" => { "timeout" => 300, "await_signal" => "container_finished", "signal_timeout" => 82_800 },
    "cleanup" => { "timeout" => 120, "always" => true, "retry" => { "max_attempts" => 2, "interval" => 5 } }
  }.freeze
  TOOL_MANIFEST = {
    "pull_image" => { "timeout" => 120 },
    "create_container" => { "timeout" => 120 },
    "start_container" => { "timeout" => 120 },
    "exec" => { "timeout" => 300 },
    "cleanup" => { "timeout" => 60, "always" => true }
  }.freeze

  class << self
    def all
      execution_scenarios + admitted_execution_scenarios + container_scenarios + admitted_container_scenarios
    end

    private

    def scenario(**) = TemporalHistories::Scenario.new(**)

    def step(id, step_run_id, auto: true, deps: [], on_failure: "fail", max_retries: 0)
      { "step_id" => id, "step_run_id" => step_run_id, "position" => id, "auto_run" => auto,
        "depends_on_step_ids" => deps, "on_failure" => on_failure, "max_retries" => max_retries,
        "skip_policy" => "never" }
    end

    def completed(step_run_id) = { "step_run_id" => step_run_id, "valid" => true }
    def failed(step_run_id) = { "step_run_id" => step_run_id, "valid" => false, "failed" => true }

    def signal_after_wait(name, *args, timer: 1)
      lambda do |driver|
        driver.await_timer(timer)
        driver.signal(name, *args)
      end
    end

    def cancel_after_wait
      lambda do |driver|
        driver.await_timer(1)
        driver.cancel
      end
    end

    # From inside an activity: the signal lands while the activity is still running.
    def signal_own_workflow(name, *args)
      context = Temporalio::Activity::Context.current
      context.client.workflow_handle(context.info.workflow_id).signal(name.to_s, *args)
    end

    def launched(step_run_id) = { "terminal_session_id" => 5000 + step_run_id, "step_run_id" => step_run_id }

    def execution_activities(steps:, mode:, complete: nil, launch: nil, skip: false, status: nil)
      activities = {
        "workflow_prepare_step_list_activity" => ->(_input, _call) { steps },
        "workflow_fetch_mode_activity" => ->(_input, _call) { { "mode" => mode } },
        "workflow_update_workflow_run_status_activity" => lambda { |input, _call|
          { "workflow_run_id" => RUN_ID, "state" => input["status"] }
        },
        "workflow_check_skip_activity" => ->(_input, _call) { { "should_skip" => skip, "reason" => nil } },
        "workflow_create_step_run_activity" => ->(_input, call) { { "step_run_id" => 900 + call } },
        "workflow_prepare_step_activity" => lambda { |input, _call|
          { "step_run_id" => input["step_run_id"], "step_id" => 1, "workflow_run_id" => RUN_ID }
        },
        "workflow_launch_step_session_activity" => launch || ->(input, _call) { launched(input["step_run_id"]) },
        "workflow_complete_step_activity" => complete || ->(input, _call) { completed(input["step_run_id"]) },
        "workflow_mark_step_skipped_activity" => lambda { |input, _call|
          { "step_run_id" => input["step_run_id"], "state" => "skipped" }
        }
      }
      activities["workflow_step_session_status_activity"] = status if status
      activities
    end

    def execution_scenario(workflow, name, steps:, mode:, drive: nil, **activity_options)
      scenario(name: name, workflow: workflow, input: { "workflow_run_id" => RUN_ID },
        activities: execution_activities(steps: steps, mode: mode, **activity_options), drive: drive)
    end

    def execution_scenarios
      workflow = Workflows::WorkflowExecutionWorkflow
      [
        execution_scenario(workflow, "empty_workflow", steps: [], mode: "non_interactive"),
        execution_scenario(workflow, "skipped_by_condition", steps: [ step(1, 11) ], mode: "non_interactive", skip: true),
        execution_scenario(workflow, "steps_waiting_on_each_other",
          steps: [ step(1, 11, deps: [ 2 ]), step(2, 12, deps: [ 1 ]) ], mode: "non_interactive"),
        execution_scenario(workflow, "auto_steps_in_dependency_order",
          steps: [ step(1, 11), step(2, 12, deps: [ 1 ]) ], mode: "non_interactive",
          drive: lambda { |driver|
            signal_after_wait(:container_finished, 11).call(driver)
            signal_after_wait(:container_finished, 12, timer: 2).call(driver)
          }),
        execution_scenario(workflow, "approved_interactive_step",
          steps: [ step(1, 11, auto: false) ], mode: "interactive", drive: signal_after_wait(:step_completed, 11)),
        execution_scenario(workflow, "skipped_by_user",
          steps: [ step(1, 11, auto: false) ], mode: "interactive", drive: signal_after_wait(:step_skipped, 11)),
        execution_scenario(workflow, "retried_by_user",
          steps: [ step(1, 11, auto: false) ], mode: "interactive",
          drive: lambda { |driver|
            signal_after_wait(:step_retried, { "old_step_run_id" => 11, "new_step_run_id" => 21 }).call(driver)
            signal_after_wait(:step_completed, 21, timer: 2).call(driver)
          }),
        execution_scenario(workflow, "failed_step_retried_by_policy",
          steps: [ step(1, 11, on_failure: "retry", max_retries: 1) ], mode: "non_interactive",
          complete: ->(input, call) { call.zero? ? failed(input["step_run_id"]) : completed(input["step_run_id"]) },
          drive: lambda { |driver|
            signal_after_wait(:container_finished, 11).call(driver)
            signal_after_wait(:container_finished, 900, timer: 2).call(driver)
          }),
        execution_scenario(workflow, "retry_finished_during_launch",
          steps: [ step(1, 11, on_failure: "retry", max_retries: 1) ], mode: "non_interactive",
          complete: ->(input, call) { call.zero? ? failed(input["step_run_id"]) : completed(input["step_run_id"]) },
          launch: lambda { |input, call|
            signal_own_workflow(:container_finished, input["step_run_id"]) if call == 1
            launched(input["step_run_id"])
          },
          drive: signal_after_wait(:container_finished, 11)),
        execution_scenario(workflow, "failed_step_skipped_by_policy",
          steps: [ step(1, 11, on_failure: "skip") ], mode: "non_interactive",
          complete: ->(input, _call) { failed(input["step_run_id"]) },
          drive: signal_after_wait(:container_finished, 11)),
        execution_scenario(workflow, "cancelled_while_waiting",
          steps: [ step(1, 11, auto: false) ], mode: "interactive", drive: signal_after_wait(:workflow_cancelled))
      ]
    end

    # One answer per poll; the last one repeats.
    def session_status(*answers)
      lambda { |_input, call|
        cancelled, sessions = answers[[ call, answers.size - 1 ].min]
        { "cancelled" => cancelled, "sessions" => sessions }
      }
    end

    def session(state, step_state = "running") = { "11" => { "state" => state, "step_state" => step_state } }

    def admitted_execution_scenarios
      workflow = Workflows::WorkflowExecutionWorkflowV2
      [
        execution_scenario(workflow, "empty_workflow", steps: [], mode: "non_interactive"),
        execution_scenario(workflow, "skipped_by_condition", steps: [ step(1, 11) ], mode: "non_interactive", skip: true),
        execution_scenario(workflow, "auto_step_finishes",
          steps: [ step(1, 11) ], mode: "non_interactive",
          status: session_status([ false, session("running") ], [ false, session("finished") ]),
          drive: signal_after_wait(:container_finished, 11)),
        execution_scenario(workflow, "approved_interactive_step",
          steps: [ step(1, 11, auto: false) ], mode: "interactive",
          status: session_status([ false, session("ready") ], [ false, session("ready", "completed") ]),
          drive: signal_after_wait(:step_completed, 11)),
        execution_scenario(workflow, "skipped_by_user",
          steps: [ step(1, 11, auto: false) ], mode: "interactive",
          status: session_status([ false, session("ready") ], [ false, session("ready", "skipped") ]),
          drive: signal_after_wait(:step_skipped, 11)),
        execution_scenario(workflow, "cancelled_while_queued",
          steps: [ step(1, 11) ], mode: "non_interactive",
          status: session_status([ false, session("queued") ], [ true, session("cancelled", "cancelled") ]),
          drive: signal_after_wait(:workflow_cancelled)),
        execution_scenario(workflow, "skip_written_before_its_signal",
          steps: [ step(1, 11, auto: false) ], mode: "interactive",
          status: session_status([ false, session("ready", "skipped") ]),
          drive: ->(driver) { driver.signal(:step_skipped, 11) if driver.await_timer_unless_closed(1) })
      ]
    end

    def container_state(input)
      { "session_id" => input["session_id"], "container_id" => "container-1", "phase" => input["phase"] }
    end

    def container_scenarios
      workflow = Workflows::ContainerWorkflow
      session_input = { "session_id" => 77, "manifest" => SESSION_MANIFEST }
      phases = ->(input, _call) { container_state(input) }
      [
        scenario(name: "agent_session", workflow: workflow, input: session_input,
          activities: { "container_phase_activity" => phases }, drive: signal_after_wait(:container_finished)),
        scenario(name: "agent_completed_during_exec", workflow: workflow, input: session_input,
          activities: { "container_phase_activity" => lambda { |input, _call|
            input["phase"] == "exec" ? container_state(input).merge("agent_completed" => true) : container_state(input)
          } }),
        scenario(name: "tool_run", workflow: workflow,
          input: { "tool_id" => 5, "tool_result_id" => 6, "project_id" => 3, "parameters" => {}, "timeout" => 300,
                   "manifest" => TOOL_MANIFEST },
          activities: { "container_phase_activity" => lambda { |input, _call|
            input["phase"] == "exec" ? { "tool_result_id" => 6, "exit_code" => 0, "status" => "done" } : {}
          } }),
        scenario(name: "failed_exec", workflow: workflow, input: session_input, outcome: :failed,
          activities: { "container_phase_activity" => lambda { |input, _call|
            if input["phase"] == "exec"
              raise Temporalio::Error::ApplicationError.new("exec failed",
                type: "ContainerService::PhaseError", non_retryable: true)
            end

            container_state(input)
          } }),
        scenario(name: "cancelled_while_running", workflow: workflow, input: session_input, outcome: :cancelled,
          activities: { "container_phase_activity" => phases }, drive: cancel_after_wait)
      ]
    end

    def admitted_container_scenarios
      workflow = Workflows::ContainerWorkflowV2
      input = { "session_id" => 77, "admission_id" => 88, "permit_token" => "permit", "manifest" => SESSION_MANIFEST }
      [
        scenario(name: "admitted_session", workflow: workflow, input: input,
          activities: { "container_admitted_phase_activity" => admitted_phases(cleanup_pending: 1) },
          drive: signal_after_wait(:container_finished)),
        scenario(name: "capacity_wait_and_slow_delete", workflow: workflow, input: input,
          activities: { "container_admitted_phase_activity" =>
            admitted_phases(capacity_waits: 1, cleanup_pending: 2, completed_in_exec: true) }),
        scenario(name: "cancelled_while_running", workflow: workflow, input: input, outcome: :cancelled,
          activities: { "container_admitted_phase_activity" => admitted_phases(cleanup_pending: 1) },
          drive: cancel_after_wait)
      ]
    end

    def admitted_phases(capacity_waits: 0, cleanup_pending: 0, completed_in_exec: false)
      seen = Hash.new(0)
      lambda { |input, _call|
        phase = input["phase"]
        seen[phase] += 1
        next { "capacity_wait" => true } if phase == "create_container" && seen[phase] <= capacity_waits
        next { "cleanup_pending" => true } if phase == "cleanup" && seen[phase] <= cleanup_pending

        state = container_state(input)
        completed_in_exec && phase == "exec" ? state.merge("agent_completed" => true) : state
      }
    end
  end
end
