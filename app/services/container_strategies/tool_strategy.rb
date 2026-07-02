# frozen_string_literal: true

require "temporalio/error"
require "temporalio/activity"

module ContainerStrategies
  # Shared base for all tool container execution (custom + internal).
  # Handles: lifecycle phases, timeout, result persistence to ToolResult.
  #
  # Subclasses implement: resolve_image, build_cmd, build_working_dir,
  # build_env_vars, build_labels, build_host_config.
  class ToolStrategy < BaseStrategy
    DEFAULT_TIMEOUT = 300
    MAX_TIMEOUT = 1800
    TIMEOUT_EXIT_CODE = 124

    def phase_config(phase)
      case phase
      when :exec    then { timeout: exec_timeout }
      when :cleanup then { timeout: 60, always: true }
      else               { timeout: 120 }
      end
    end

    def before_create_container(**)
      {
        image: resolve_image,
        cmd: build_cmd,
        working_dir: build_working_dir,
        env_vars: build_env_vars,
        labels: build_labels,
        host_config: build_host_config
      }
    end

    def start_container(container_id:, **)
      container = resolve_container(container_id)
      runtime.start_container(container)
      {}
    end

    # Waited in short slices with Temporal heartbeats between them: activities
    # must heartbeat to receive cancellation at all (a non-heartbeating
    # activity blocks until its own timeout even after tasks/cancel or a
    # workflow cancel), and the heartbeat timeout is the only fast detector
    # of a dead worker mid-execution.
    HEARTBEAT_SLICE = 15

    def exec(container_id:, **)
      container = resolve_container(container_id)
      start_time = Time.current

      exit_code = wait_with_heartbeat(container, exec_timeout)
      return handle_timeout(container, start_time) if exit_code.nil?

      logs = runtime.container_logs(container)
      persist_result(exit_code: exit_code, stdout: logs[:stdout].to_s,
                     stderr: logs[:stderr].to_s, duration_ms: ms_since(start_time))

      { tool_result_id: input[:tool_result_id], exit_code: exit_code, status: "done" }
    rescue Temporalio::Error::CanceledError
      cancel_execution(container, start_time)
      raise
    end

    private

    def exec_timeout
      [ input[:timeout] || DEFAULT_TIMEOUT, MAX_TIMEOUT ].min
    end

    # Returns the container's exit code, or nil on overall timeout. Raises
    # Temporalio::Error::CanceledError when Temporal delivers a cancel (only
    # possible because we heartbeat between wait slices).
    def wait_with_heartbeat(container, timeout)
      deadline = Time.current + timeout

      loop do
        if (ctx = activity_context)
          ctx.heartbeat
          ctx.cancellation.check!
        end

        slice = [ HEARTBEAT_SLICE, (deadline - Time.current).ceil ].min
        return nil if slice <= 0

        begin
          result = runtime.wait_container(container, slice)
          return result["StatusCode"] || result[:StatusCode] || -1
        rescue Docker::Error::TimeoutError
          # Slice elapsed, container still running — heartbeat and keep waiting.
        end
      end
    end

    def activity_context
      return nil unless defined?(Temporalio::Activity::Context)

      Temporalio::Activity::Context.current_or_nil
    end

    # Cancellation delivered mid-execution: actually kill the container —
    # otherwise tasks/cancel flips workflow state while the container keeps
    # running — and leave a terminal ToolResult so pollers see a final state.
    def cancel_execution(container, start_time)
      runtime.stop_container(container, 5)
      persist_result(exit_code: -1, stdout: "", stderr: "Execution cancelled",
                     duration_ms: ms_since(start_time), error_msg: "Execution cancelled")
    rescue StandardError => e
      Rails.logger.warn("[ToolStrategy] Cancel cleanup failed: #{e.message}")
    end

    def persist_result(exit_code:, stdout:, stderr:, duration_ms:, error_msg: nil)
      return unless input[:tool_result_id]

      tr = ToolResult.find(input[:tool_result_id])
      tr.complete!(exit_code: exit_code, stdout: stdout, stderr: stderr,
                   duration_ms: duration_ms, error: error_msg)
    end

    def on_failure(error: nil, **)
      return {} if input[:tool_result_id].blank? || error.blank?

      tr = ToolResult.find(input[:tool_result_id])
      return {} unless tr.state == "processing"

      tr.update!(state: "failed", error: error.to_s.truncate(1000))
      {}
    rescue StandardError => e
      Rails.logger.error("[ToolStrategy] Failed to mark tool_result failed: #{e.message}")
      {}
    end

    def handle_timeout(container, start_time)
      container.kill rescue nil
      logs = begin
               runtime.container_logs(container)
             rescue StandardError
               { stdout: "", stderr: "" }
             end
      duration_ms = ms_since(start_time)

      persist_result(exit_code: TIMEOUT_EXIT_CODE, stdout: logs[:stdout].to_s,
                     stderr: logs[:stderr].to_s, duration_ms: duration_ms,
                     error_msg: "Timed out after #{exec_timeout}s")

      { tool_result_id: input[:tool_result_id], exit_code: TIMEOUT_EXIT_CODE, status: "failed" }
    end

    def ms_since(start_time)
      ((Time.current - start_time) * 1000).to_i
    end
  end
end
