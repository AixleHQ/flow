# frozen_string_literal: true

class Web::Company::Projects::IntegrationsController < Web::Company::Projects::ApplicationController
  def index
    integrations = Integration.visible_for_project(current_project)
                              .includes(:connected_by)
                              .order(created_at: :desc)

    render inertia: "Projects/Integrations/IntegrationsPage", props: {
      project: project_props,
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h }
    }
  end

  def create
    provider = params[:provider].to_s

    integration = case provider
    when "github"
      Github::IntegrationService.new(
        company: current_company,
        connected_by: current_user,
        project: current_project
      ).create(installation_id: params[:installation_id].to_s)
    when "gitlab"
      Gitlab::IntegrationService.new(
        company: current_company,
        connected_by: current_user,
        project: current_project
      ).create(personal_access_token: params[:personal_access_token].to_s)
    end

    if integration.nil?
      redirect_to company_project_integrations_path(current_project), alert: "Unsupported provider: #{provider}"
    elsif integration.persisted? && integration.active?
      redirect_to company_project_integrations_path(current_project), notice: "#{provider.capitalize} integration connected"
    else
      error_msg = integration.settings&.dig("error") || "Failed to connect #{provider.capitalize}"
      redirect_to company_project_integrations_path(current_project), alert: error_msg
    end
  end

  def destroy
    integration = Integration.for_project(current_project).find(params[:id])
    integration.destroy
    redirect_to company_project_integrations_path(current_project), notice: "Integration removed"
  end
end
