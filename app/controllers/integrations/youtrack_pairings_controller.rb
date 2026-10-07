# frozen_string_literal: true

# The Aixle Flow YouTrack app's side of Connect (youtrack-app/README.md,
# "Protocol with Aixle"). Public and answering CORS for any origin without
# credentials (config/initializers/cors.rb): the app calls it from a widget,
# whose origin is `null`. A pairing's secret is its only credential, so an
# unknown pairing and a wrong secret answer alike.
class Integrations::YoutrackPairingsController < ActionController::API
  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { request.remote_ip }
  rate_limit to: 120, within: 10.minutes, only: %i[show complete], by: -> { request.remote_ip }

  before_action :authenticate_pairing, only: %i[show complete]

  # A pairing started in YouTrack; a signed-in user approves it by typing its
  # code into Aixle's connect page.
  def create
    url = instance_url(params[:instance_url])
    return error(:unprocessable_content, "validation_failed", "Send the YouTrack instance URL over https") unless url

    pairing, secret = YoutrackPairing.start!(instance_url: url)
    render status: :created, json: {
      id: pairing.public_id, secret: secret, code: pairing.code, approve_url: youtrack_connect_url,
      expires_at: pairing.expires_at.iso8601
    }
  end

  def show
    render json: {
      status: @pairing.state, instance_url: @pairing.instance_url, code: @pairing.code,
      company: @pairing.company && { name: @pairing.company.name },
      project: @pairing.project && { name: @pairing.project.name },
      approved_by: @pairing.user && { name: @pairing.user.name }
    }
  end

  def complete
    @pairing.with_lock do
      return error(:conflict, "not_approved", "This pairing is #{@pairing.state}") unless @pairing.state == "approved"
      unless instance_url(params[:instance_url]) == @pairing.instance_url
        return error(:unprocessable_content, "instance_mismatch", "This pairing is for #{@pairing.instance_url}")
      end
      return error(:forbidden, "not_authorized", "The approving user can no longer connect integrations in this project") unless approver_allowed?

      integration = Youtrack::IntegrationService.new(company: @pairing.company, connected_by: @pairing.user, project: @pairing.project)
                                                .connect_app(base_url: @pairing.instance_url, token: params[:token].to_s,
                                                             login: params.dig(:service_user, :login).to_s,
                                                             project_ids: Array(params[:projects]).map { |p| p[:id].to_s },
                                                             app_version: params[:app_version])
      @pairing.complete!(integration)
      render json: { projects: subscriptions_json(integration), return_url: company_project_trackers_url(@pairing.project) }
    end
  rescue Trackers::Error => e
    error(:unprocessable_content, e.code, e.message)
  rescue Youtrack::IntegrationService::ConfigurationError => e
    error(:unprocessable_content, "validation_failed", e.message)
  end

  private

  def authenticate_pairing
    @pairing = YoutrackPairing.find_by(public_id: params[:id].to_s)
    secret = request.authorization.to_s.delete_prefix("Bearer ").strip
    error(:not_found, "not_found", "No such pairing") unless @pairing&.authentic?(secret)
  end

  def instance_url(value)
    url = Youtrack::Config.normalize_base_url(value.to_s)
    url if url&.start_with?("https://")
  end

  def approver_allowed?
    context = ProjectContext.new(@pairing.user, {}, project: @pairing.project)
    Web::Company::Projects::IntegrationsPolicy.new(context, @pairing.project).create?
  end

  def subscriptions_json(integration)
    projects = Array(integration.settings.to_h["youtrack_projects"]).index_by { |p| p["id"].to_s }
    integration.tracker_subscriptions.live.where(external_scope_id: projects.keys).map do |subscription|
      project = projects.fetch(subscription.external_scope_id)
      { id: subscription.external_scope_id, events_url: Trackers::Youtrack::Webhooks.url(subscription), secret: subscription.secret,
        status_field: project["status_field"], assignee_field: project["assignee_field"] }
    end
  end

  def error(status, code, message)
    render status: status, json: { error: code.to_s, message: message }
  end
end
