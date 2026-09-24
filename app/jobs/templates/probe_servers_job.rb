# frozen_string_literal: true

module Templates
  # The one network step of a template install, run after the install commits:
  # ask each MCP server it created whether it needs a sign-in. The manifest
  # cannot say (MCP::ConnectorInstaller explains why), and a server that
  # answers 401 gets auth_type oauth and a "Connect" checklist item.
  #
  # A probe that fails leaves a "check again" item instead. Items are keyed by
  # server, so re-running this updates them rather than adding more.
  class ProbeServersJob < ApplicationJob
    queue_as :default

    def perform(template_install_id, server_ids)
      install = TemplateInstall.find_by(id: template_install_id) or return

      MCPServer.where(id: server_ids, scope: install.project).find_each do |server|
        probe(install, server)
      end
    end

    private

    def probe(install, server)
      outcome = MCP::ToolDriftDetector.capture(server)
      if outcome.status == :unauthorized && server.auth_type_none? && !server.transport_stdio?
        server.update!(auth_type: :oauth)
      end

      if server.auth_type_oauth?
        upsert(install, server, kind: "oauth", status: "pending")
      elsif outcome.status == :error
        upsert(install, server, kind: "probe", status: "failed")
      end
    end

    def upsert(install, server, kind:, status:)
      item = install.setup_items.find_or_initialize_by(ref: "#{kind}:#{server.id}")
      item.update!(kind: kind, status: status, position: item.position || 0,
                   detail: { "server_id" => server.id, "name" => server.name })
    end
  end
end
