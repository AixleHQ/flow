# frozen_string_literal: true

module InternalTools
  # coder_ssh_exec — run a shell command on a Coder workspace previously
  # allocated by this terminal session. The command runs in the Rails
  # process via `coder ssh -- sh -c <command>`; the integration token is
  # passed via the process environment and never appears in argv.
  #
  # The session-ownership check enforces that the calling session is the
  # one that holds the workspace lock (DD-5). Output is bounded by a
  # single total-response budget (DD-15).
  class CoderSshExec < Base
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

      runner = Coder::SshRunner.new(coder_integration)
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
  end
end
