# frozen_string_literal: true

# The accounts the person connected and what agents may do with them in each project of
# the current company (docs/design/github-user-identity.md §4.2).
class Web::Profile::ConnectionsController < Web::ApplicationController
  PROVIDER = Github::UserConnection::PROVIDER

  layout "inertia"

  before_action :require_auth

  def index
    render inertia: "Profile/Connections", props: {
      available: UserConnections.available?(provider: PROVIDER),
      github: -> {
        credential = UserConnections.connection(user: current_user, provider: PROVIDER)
        credential && UserConnectionResource.new(credential).to_h
      },
      consents: -> {
        UserConnections.consents(user: current_user, company: current_company, provider: PROVIDER)
                       .map { |consent| ActAsConsentResource.new(consent).to_h }
      }
    }
  end

  def destroy
    UserConnections.disconnect!(user: current_user, provider: params[:provider])
    redirect_to profile_connections_path, notice: "GitHub disconnected"
  rescue UserConnections::UnknownProvider
    head :not_found
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
