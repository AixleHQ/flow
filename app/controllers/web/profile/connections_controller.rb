# frozen_string_literal: true

# The accounts the person connected and what agents may do with them in each project of
# the current company (docs/design/github-user-identity.md §4.2).
class Web::Profile::ConnectionsController < Web::ApplicationController
  layout "inertia"

  before_action :require_auth
  before_action :refuse_impersonation, only: :destroy

  def index
    render inertia: "Profile/Connections", props: {
      available: UserConnections.available_providers,
      connections: -> {
        UserConnections.connections_of(user: current_user).transform_values do |credential|
          credential && UserConnectionResource.new(credential).to_h
        end
      },
      consents: -> {
        UserConnections.consents_of(user: current_user, company: current_company).transform_values do |rows|
          rows.map { |consent| ActAsConsentResource.new(consent).to_h }
        end
      }
    }
  end

  def destroy
    provider = params[:provider]
    UserConnections.disconnect!(user: current_user, provider: provider)
    redirect_to profile_connections_path, notice: "#{UserConnections.label(provider: provider)} disconnected"
  rescue UserConnections::UnknownProvider
    head :not_found
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # The connection decides what agents may do as the person, so an operator
  # impersonating them does not change it (docs/design/github-user-identity.md §4.2).
  def refuse_impersonation
    return unless impersonated?

    redirect_to profile_connections_path, alert: "Connected accounts cannot be changed while impersonating."
  end
end
