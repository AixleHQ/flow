# frozen_string_literal: true

module ContextBuilders
  class SessionInfo < Base
    def build
      lines = [ "## Session Context" ]
      lines << ""
      lines << "You are running in a standalone #{session.mode} agent session on the Aixle platform."
      lines << ""
      lines << "- **Session ID:** #{session.id}"
      lines << "- **Agent Runtime:** #{session.agent_type}"
      lines << "- **Mode:** #{session.mode}"
      lines << "- **Project:** #{project.name}" if project.present?

      [ section(
        tag: "session-context",
        priority: :info,
        content: lines.join("\n")
      ) ]
    end
  end
end
