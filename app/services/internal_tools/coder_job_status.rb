# frozen_string_literal: true

module InternalTools
  # coder_job_status — poll a command started by `coder_ssh_exec` with
  # `detach: true`. Reads the job's pid / exit-code / metadata / heartbeat / log
  # files on the workspace; each call is a short SSH round trip, so polling is
  # safe where running the work in the foreground is not.
  class CoderJobStatus < Base
    tool do
      display_name "Coder: Job Status"
      description "Check a detached command started by coder_ssh_exec (detach: true). " \
                  "Returns `state` (running | exited | died | unknown), the `exit_code` once it has finished, " \
                  "and the tail of its log. Poll this instead of re-running a long command. " \
                  "A finished or interrupted job also carries its lifecycle metadata — `reason` " \
                  "(completed | command_failed | timeout | signaled | runner_vanished), `signal`, `started_at`, " \
                  "`finished_at`, `elapsed_seconds`, `pid`, `pgid`, `command` — and a one-line `diagnosis`: " \
                  "read `reason` before concluding anything about a job that did not exit 0, because it separates " \
                  "a failing command from a cancellation, a timeout and a runner that vanished. " \
                  "`exited` means the command itself was reaped, never merely signalled: a cancelled job stays " \
                  "`running` until it has really ended, and one that had to be killed says so in `escalated_to`. " \
                  "`runner_vanished` is deliberately ambiguous: a hard kill of the job's process group and an " \
                  "infrastructure failure leave identical evidence, so it also carries `possible_causes` and its " \
                  "`diagnosis` names both instead of asserting one."
      tags :coder
      inject_when :coder_integration_connected
      requires_integration :coder
      input_schema({
        type: "object",
        required: %w[workspace_name job_id],
        properties: {
          workspace_name: {
            type: "string",
            description: "Workspace the job was started on."
          },
          job_id: {
            type: "string",
            description: "job_id returned by coder_ssh_exec when it was called with detach: true."
          },
          tail_lines: {
            type: "integer",
            description: "How many trailing log lines to return. Default 40."
          }
        }
      })
    end

    include Concerns::CoderResolver

    def execute
      require_coder!

      workspace_name = params[:workspace_name].to_s
      job_id         = params[:job_id].to_s

      return error("workspace_name is required") if workspace_name.empty?
      return error("job_id is required") if job_id.empty?

      lock_service = Coder::LockService.new(coder_integration)
      unless lock_service.held_by_session?(workspace_name: workspace_name, terminal_session_id: session.id)
        return error("session does not hold the lock for workspace #{workspace_name}")
      end

      lock_service.touch(workspace_name: workspace_name, terminal_session_id: session.id)

      status = Coder::SshRunner.new(coder_integration).job_status(
        workspace_name: workspace_name,
        job_id:         job_id,
        tail_lines:     params[:tail_lines]
      )

      success(status.to_json)
    rescue Concerns::CoderResolver::NotConfiguredError => e
      error(e.message)
    rescue Coder::SshRunner::CommandError => e
      error("coder_job_status: #{e.message}")
    end
  end
end
