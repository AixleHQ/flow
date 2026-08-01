# frozen_string_literal: true

# Installing from the public connector catalog.
#
# There is no index here on purpose: a connector is not a resource of its own,
# it is a pre-described way to create an MCPServer. The catalog is therefore
# browsed from the MCP servers page (which serves the `connectors` prop) and this
# controller only performs the install, landing back on that same page.
class Web::Company::Projects::ConnectorsController < Web::Company::Projects::ApplicationController
  def create
    connector = Connector.find_by(name: params[:connector_name])
    return redirect_back_with(alert: "Connector not found") if connector.nil?

    result = MCP::ConnectorInstaller.call(
      connector: connector, target_id: params[:target_id], values: install_values, project: current_project
    )

    redirect_to company_project_mcp_servers_path(current_project), notice: install_notice(result)
  rescue MCP::ConnectorInstaller::Error => e
    redirect_back_with(alert: e.message)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_with(alert: e.record.errors.full_messages.join(", "))
  end

  private

  # Input keys are the registry's, not ours: header names like
  # "payment-signature" and env vars like "LINEAR_PAT" must survive verbatim.
  # Without this the global key-underscoring would rewrite them and every
  # submitted value would fail to match its declared input.
  def preserved_param_paths
    [ [ :values ] ]
  end

  # Input keys are declared per connector, so they cannot be enumerated in a
  # strong-parameters list up front. Instead of `permit!`-ing the hash wholesale,
  # coerce it to scalars (and arrays of scalars, for repeated arguments) here:
  # nested structures are dropped at the door rather than trusted to be ignored
  # later. Downstream, MCP::ConnectorAttributes reads ONLY the keys the manifest
  # declares, so an extra key cannot smuggle in a header or env var either.
  SCALAR_TYPES = [ String, Numeric, TrueClass, FalseClass ].freeze

  def install_values
    raw = params[:values]
    return {} unless raw.respond_to?(:to_unsafe_h)

    raw.to_unsafe_h.each_with_object({}) do |(key, value), memo|
      coerced = coerce_value(value)
      memo[key.to_s] = coerced unless coerced.nil?
    end
  end

  def coerce_value(value)
    return value.to_s if SCALAR_TYPES.any? { |type| value.is_a?(type) }
    return nil unless value.is_a?(Array)

    scalars = value.select { |item| SCALAR_TYPES.any? { |type| item.is_a?(type) } }.map(&:to_s)
    scalars.presence
  end

  def install_notice(result)
    base = "#{result.server.name} installed"
    base = "#{base} (registry unreachable — installed from the last mirrored copy)" if result.stale
    # Detected, not assumed: the server answered 401. Say so plainly, because an
    # installed-but-unauthenticated connector looks identical to a working one
    # until an agent tries to use it.
    return base unless result.needs_auth

    "#{base}. It requires sign-in — connect it to finish setup."
  end

  def redirect_back_with(alert:)
    redirect_to company_project_mcp_servers_path(current_project), alert: alert
  end
end
