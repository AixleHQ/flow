# frozen_string_literal: true

# What a person allows agents to do with a connected account in one project.
class Web::Profile::ActAsConsentsController < Web::ApplicationController
  SWITCHES = %i[in_own_tasks in_others_tasks].freeze

  before_action :require_auth
  before_action :refuse_impersonation

  # PATCH /profile/connections/:connection_provider/act_as_consents/:project_id
  # Body: { inOwnTasks?: boolean, inOthersTasks?: boolean }. A switch left out stays as it is.
  # Strict: the body must name at least one switch, may name nothing else, and each switch
  # is a JSON boolean.
  def update
    switches = permitted_switches
    unless switches
      return render json: { error: "Send inOwnTasks and/or inOthersTasks, each true or false." },
                    status: :unprocessable_entity
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

  # { in_own_tasks: bool, in_others_tasks: bool } for the switches the body names, or nil
  # when the body names none, names another key, or gives a value that is not a boolean.
  def permitted_switches
    body = request.request_parameters
    names = body.keys.map { |key| key.to_s.underscore }
    return nil if names.empty? || (names - SWITCHES.map(&:to_s)).any?

    switches = names.index_with { |name| params[name] }.symbolize_keys
    switches if switches.values.all? { |value| [ true, false ].include?(value) }
  end

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # The switches decide whether other people's agents may take the person's GitHub
  # token, so an operator impersonating them does not flip them
  # (docs/design/github-user-identity.md §4.2).
  def refuse_impersonation
    return unless impersonated?

    render json: { error: "Consents cannot be changed while impersonating." }, status: :forbidden
  end
end
