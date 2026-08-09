# frozen_string_literal: true

module InternalTools
  # coder_allocate_machine — claim a Coder workspace for the current
  # terminal session. Returns the allocated workspace identity (id, name,
  # status, ssh command, lock expiry). The Coder URL and session token
  # never cross the MCP boundary (N1 / DD-1).
  class CoderAllocateMachine < Base
    tool do
      display_name "Coder: Allocate Machine"
      description "Allocate a Coder workspace for the current terminal session. Picks a healthy available workspace from the integration's pool " \
                  "(or creates one if a default template is configured), locks it to the current terminal session, and returns the workspace " \
                  "identity (name, id, ssh command, lock expiry). Workspaces are health-checked before hand-over; if none is healthy the least-bad " \
                  "one is returned with a `health_warning`. If the allocated workspace turns out to be unusable, call this again with `exclude` " \
                  "set to its name instead of releasing and retrying — a plain retry returns the same workspace."
      tags :coder
      inject_when :coder_integration_connected
      requires_integration :coder
      input_schema({
        type: "object",
        required: [],
        properties: {
          note: {
            type: "string",
            description: "Optional free-form note recorded on the workspace lock (audit / debug aid). Do NOT include the task id or task link — task context is derived server-side."
          },
          exclude: {
            type: "array",
            items: { type: "string" },
            description: "Workspace names this session will not accept — e.g. one that just failed to run anything. Skipped before locking."
          }
        }
      })
    end

    include Concerns::CoderResolver

    def execute
      require_coder!

      result = Coder::Allocator.new(
        integration:      coder_integration,
        terminal_session: session
      ).allocate(
        note:        params[:note],
        acquired_by: acquired_by_label,
        exclude:     Array(params[:exclude])
      )

      success(result.to_json)
    rescue Concerns::CoderResolver::NotConfiguredError => e
      error(e.message)
    rescue Coder::TokenService::AuthenticationError,
           Coder::TokenService::ConfigurationError,
           Coder::WorkspaceService::OperationError,
           Coder::LockService::LockNotAcquired,
           Coder::Allocator::ExhaustedError => e
      error("coder_allocate_machine: #{e.class.name.demodulize}: #{e.message}")
    end

    private

    def acquired_by_label
      [ session.try(:user)&.email, session.id ].compact.join("#")
    end
  end
end
