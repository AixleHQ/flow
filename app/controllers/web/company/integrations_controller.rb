# frozen_string_literal: true

class Web::Company::IntegrationsController < Web::Company::ApplicationController
  skip_before_action :dynamic_authorize!, only: :github_setup

  def index
    integrations = current_company.integrations
                                  .company_wide
                                  .includes(:connected_by)
                                  .order(created_at: :desc)

    render inertia: "Company/Integrations/Index", props: {
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h }
    }
  end

  def github_setup
    target_project = resolve_github_setup_project(params[:state])
    installation_id = params[:installation_id]

    if installation_id.blank?
      redirect_to github_setup_redirect_path(target_project)
      return
    end

    if target_project.present? && !target_project.accessible_by?(current_user)
      redirect_to company_integrations_path
      return
    end

    integration = Integration.find_or_build_github_for_installation(
      company: current_company,
      connected_by: current_user,
      project: target_project,
      installation_id: installation_id
    )
    integration.credentials_data = { installation_id: installation_id.to_s }

    begin
      info = Github::TokenService.new(integration).verify_installation
      integration.name = info[:account_login]
      integration.settings = {
        account_type: info[:account_type],
        target_type: info[:target_type]
      }
      integration.status = :active
    rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
      integration.name ||= "GitHub (unverified)"
      integration.status = :error
      integration.settings = { error: e.message }
    end

    integration.save
    redirect_to github_setup_redirect_path(target_project),
                notice: integration.active? ? "GitHub connected" : "GitHub connection failed — check integration status"
  end

  def create
    provider = params[:provider].to_s

    case provider
    when "gitlab"
      integration = Gitlab::IntegrationService.new(
        company: current_company,
        connected_by: current_user
      ).create(personal_access_token: params[:personal_access_token].to_s)

      finish_create(integration, label: "GitLab")
    when "coder"
      integration = Coder::IntegrationService.new(
        company: current_company,
        connected_by: current_user
      ).create(
        coder_url:        params[:coder_url].to_s,
        session_token:    params[:session_token].to_s,
        default_template: params[:default_template].presence,
        machine_prefix:   params[:machine_prefix].presence,
        lock_ttl_minutes: params[:lock_ttl_minutes].presence
      )

      finish_create(integration, label: "Coder")
    else
      redirect_to company_integrations_path, alert: "Unsupported provider: #{provider}"
    end
  end

  def destroy
    integration = current_company.integrations.find(params[:id])
    integration.destroy
    redirect_to company_integrations_path, notice: "Integration removed"
  end

  private

  def finish_create(integration, label:)
    if integration.persisted? && integration.active?
      redirect_to company_integrations_path, notice: "#{label} integration connected"
    else
      error_msg = integration.settings&.dig("error") || "Failed to connect #{label}"
      redirect_to company_integrations_path, alert: error_msg
    end
  end

  def github_setup_redirect_path(project)
    project ? company_project_integrations_path(project) : company_integrations_path
  end

  def resolve_github_setup_project(state)
    return nil if state.blank?

    match = state.to_s.match(/\Aproject:(\d+)\z/)
    return nil unless match

    current_company.projects.find_by(id: match[1].to_i)
  end
end
