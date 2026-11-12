# frozen_string_literal: true

# What a person allows agents to do with a connected account in one project.
class Web::Profile::ActAsConsentsController < Web::ApplicationController
  SWITCHES = %i[in_own_tasks in_others_tasks].freeze

  before_action :require_auth

  # PATCH /profile/connections/:connection_provider/act_as_consents/:project_id
  # Body: { inOwnTasks?: boolean, inOthersTasks?: boolean }. A switch left out stays as it is.
  def update
    switches = SWITCHES.select { |name| params.key?(name) }.index_with { |name| params[name] }
    unless switches.values.all? { |value| [ true, false ].include?(value) }
      return render json: { error: "inOwnTasks and inOthersTasks must be booleans" }, status: :unprocessable_entity
    end

    consent = UserConnections.update_consent!(
      user: current_user, company: current_company, provider: params[:connection_provider],
      project_id: params[:project_id], **switches
    )
    render json: ActAsConsentResource.new(consent).to_h
  rescue UserConnections::UnknownProvider, UserConnections::ProjectNotFound
    head :not_found
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
