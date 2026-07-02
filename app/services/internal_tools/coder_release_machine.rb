# frozen_string_literal: true

module InternalTools
  # coder_release_machine — release the workspace lock held by the current
  # terminal session for the given workspace. Idempotent (DD-8) — returns
  # success whether or not a lock row existed.
  class CoderReleaseMachine < Base
    tool do
      display_name "Coder: Release Machine"
      description "Release the Coder workspace lock for the given workspace. Idempotent — returns success whether or not a lock was held. The step's teardown also auto-releases any locks held by this session."
      tags :coder
      managed_mcp_provider :coder
      requires_integration :coder
      input_schema({
        type: "object",
        required: %w[workspace_name],
        properties: {
          workspace_name: {
            type: "string",
            description: "Workspace name returned by coder_allocate_machine."
          }
        }
      })
    end

    include Concerns::CoderResolver

    def execute
      require_coder!

      workspace_name = params[:workspace_name].to_s
      return error("workspace_name is required") if workspace_name.empty?

      lock_service = Coder::LockService.new(coder_integration)
      held_by_self = lock_service.held_by_session?(
        workspace_name:      workspace_name,
        terminal_session_id: session.id
      )

      # DD-13: only the lock holder may release. Without this gate any session
      # could delete another session's row (LockService#release is a scoped
      # delete_all on the workspace key).
      lock_service.release(workspace_name: workspace_name) if held_by_self

      success({
        workspace_name: workspace_name,
        released:       held_by_self
      }.to_json)
    rescue Concerns::CoderResolver::NotConfiguredError => e
      error(e.message)
    end
  end
end
