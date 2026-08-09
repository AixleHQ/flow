# frozen_string_literal: true

module InternalTools
  # coder_ssh_exec — run a shell command on a Coder workspace previously
  # allocated by this terminal session. The command runs in the Rails
  # process via `coder ssh <workspace> -- <command>`; the integration token is
  # passed via the process environment and never appears in argv.
  #
  # The session-ownership check enforces that the calling session is the
  # one that holds the workspace lock (DD-5). Output is bounded by a
  # single total-response budget (DD-15).
  class CoderSshExec < Base
    tool do
      display_name "Coder: Run Command (SSH)"
      description "Run a shell command on a Coder workspace previously allocated by this step. " \
                  "Returns the exit code, stdout, stderr, and a `truncated` marker if the response exceeded the inline budget. " \
                  "A foreground call cannot outlive the MCP transport ceiling (about 2 minutes) no matter what `timeout_seconds` says, " \
                  "and a timeout kills the SSH channel, NOT the remote work — a test suite or build started by `docker compose` keeps running. " \
                  "For anything long (test suites, builds, full check runs) pass `detach: true`: it returns a `job_id` in seconds, " \
                  "then poll `coder_job_status`. Never re-issue a command that timed out."
      tags :coder
      inject_when :coder_integration_connected
      requires_integration :coder
      input_schema({
        type: "object",
        required: %w[workspace_name command],
        properties: {
          command: {
            type: "string",
            description: "Shell command to execute (run via sh -c)."
          },
          workspace_name: {
            type: "string",
            description: "Workspace name returned by coder_allocate_machine."
          },
          timeout_seconds: {
            type: "integer",
            description: "Per-call timeout in seconds for a foreground run. Default 60. " \
                         "Values above the transport ceiling (about 120s) cannot be honoured — use `detach` instead."
          },
          detach: {
            type: "boolean",
            description: "Start the command detached from this call and return immediately with a `job_id` " \
                         "(poll it with coder_job_status). Use for anything that can run longer than a minute."
          }
        }
      })
    end

    include Concerns::CoderResolver

    def execute
      require_coder!

      workspace_name = params[:workspace_name].to_s
      command        = params[:command].to_s
      timeout        = params[:timeout_seconds].presence

      return error("workspace_name is required") if workspace_name.empty?
      return error("command is required") if command.empty?

      lock_service = Coder::LockService.new(coder_integration)
      unless lock_service.held_by_session?(workspace_name: workspace_name, terminal_session_id: session.id)
        return error("session does not hold the lock for workspace #{workspace_name}")
      end

      # Renew on use: the lock's TTL then measures silence rather than time
      # since allocation, so a session that dies hard frees the workspace after
      # one idle window instead of holding it for the whole TTL, and a long
      # gate never loses its box mid-run.
      lock_service.touch(workspace_name: workspace_name, terminal_session_id: session.id)

      runner = Coder::SshRunner.new(coder_integration)
      return detach(runner, workspace_name, command) if detach?

      result = runner.exec(
        workspace_name: workspace_name,
        command:        command,
        timeout:        timeout
      )

      payload = {
        exit_code: result[:exit_code],
        stdout:    result[:stdout],
        stderr:    result[:stderr],
        truncated: result[:truncated]
      }
      payload[:stdout_bytes_total] = result[:stdout_bytes_total] if result[:stdout_bytes_total]
      payload[:stderr_bytes_total] = result[:stderr_bytes_total] if result[:stderr_bytes_total]

      success(payload.to_json)
    rescue Concerns::CoderResolver::NotConfiguredError => e
      error(e.message)
    rescue Coder::SshRunner::CommandError => e
      error("coder_ssh_exec: #{e.message}")
    end

    private

    def detach?
      ActiveModel::Type::Boolean.new.cast(params[:detach]) == true
    end

    def detach(runner, workspace_name, command)
      started = runner.exec_detached(workspace_name: workspace_name, command: command)

      success(started.merge(
        next_step: "poll coder_job_status with this job_id; do not re-run the command"
      ).to_json)
    end
  end
end
