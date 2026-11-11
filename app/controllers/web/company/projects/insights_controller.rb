# frozen_string_literal: true

# The company's connection to Aixle Insights and this project's switches
# (docs/design/insights-usage-export.md §5). Every action answers on the project's
# Integrations page; a refused code comes back against the field so the dialog stays open.
class Web::Company::Projects::InsightsController < Web::Company::Projects::ApplicationController
  def connect
    service.connect(company: current_project.company, user: current_user, code: params[:code])
    redirect_to integrations_page, notice: "Connected to Aixle Insights"
  rescue Insights::ConnectionService::Error => e
    redirect_to integrations_page, inertia: { errors: { code: e.message } }
  end

  def rotate
    service.rotate!(connection!)
    redirect_to integrations_page, notice: "The Insights connection has a new secret"
  rescue Insights::ConnectionService::Error => e
    redirect_to integrations_page, alert: e.message
  end

  def disconnect
    service.disconnect!(connection!)
    redirect_to integrations_page, notice: "Disconnected from Aixle Insights"
  rescue Insights::ConnectionService::Error => e
    redirect_to integrations_page, alert: e.message
  end

  # Prompt sharing only on an exported project: turning export off turns it off too.
  def update
    current = current_project.insights_settings
    export = params.key?(:export) ? ActiveModel::Type::Boolean.new.cast(params[:export]) : current["export"]
    share = params.key?(:share_prompts) ? ActiveModel::Type::Boolean.new.cast(params[:share_prompts]) : current["share_prompts"]
    mapped = params.key?(:insights_project_id) ? params[:insights_project_id].presence : current["project_id"]

    current_project.update!(settings: current_project.settings.to_h.merge(
      "insights" => { "export" => export == true, "share_prompts" => export == true && share == true, "project_id" => mapped }
    ))
    Insights::BackfillJob.perform_later(current_project.id) if export == true && current["export"] != true
    redirect_to integrations_page, notice: "Insights settings saved"
  end

  def projects
    render json: { projects: service.projects(connection!).map { |p| p.slice("id", "name") } }
  rescue Insights::ConnectionService::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def service
    @service ||= Insights::ConnectionService.new
  end

  def connection!
    Integration.find_by!(company_id: current_project.company_id, project_id: nil, provider: "insights")
  end

  def integrations_page
    company_project_integrations_path(current_project)
  end
end
