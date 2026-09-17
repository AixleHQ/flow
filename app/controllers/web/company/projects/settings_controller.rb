# frozen_string_literal: true

class Web::Company::Projects::SettingsController < Web::Company::Projects::ApplicationController
  def show
    render inertia: "Projects/Settings/SettingsPage", props: {
      project: settings_project_props
    }
  end

  def update
    if insights_sharing_param_present? && !can_manage_insights_sharing?
      return redirect_back fallback_location: company_project_settings_path(current_project),
                           alert: "Not authorized to manage Insights sharing"
    end

    if current_project.update(project_params)
      redirect_to company_project_settings_path(current_project), notice: "Project updated successfully"
    else
      redirect_back fallback_location: company_project_settings_path(current_project),
                     inertia: { errors: current_project.errors }
    end
  end

  def regenerate_insights_connection_token
    unless current_project.share_usage_with_insights?
      return redirect_to company_project_settings_path(current_project),
                         alert: "Enable Insights sharing before generating a connection token"
    end

    session[:insights_connection_token_plaintext] = current_project.regenerate_insights_connection_token!
    redirect_to company_project_settings_path(current_project),
                notice: "Insights connection token generated — copy it now, it won't be shown again"
  end

  private

  def project_params
    permitted = [ :name, :description, :preferred_artifacts_language, :state ]
    permitted << :share_usage_with_insights if can_manage_insights_sharing?
    params.require(:project).permit(*permitted)
  end

  def insights_sharing_param_present?
    project_hash = params[:project]
    return false unless project_hash.respond_to?(:key?)

    project_hash.key?(:share_usage_with_insights)
  end

  def can_manage_insights_sharing?
    Web::Company::Projects::SettingsPolicy.new(policy_context, current_project).manage_insights_sharing?
  end

  def settings_project_props
    project = current_project
    {
      id: project.id,
      name: project.name,
      description: project.description,
      slug: project.slug,
      state: project.state,
      preferred_artifacts_language: project.preferred_artifacts_language,
      created_at: project.created_at.iso8601,
      updated_at: project.updated_at.iso8601,
      owner_name: project.owner.name,
      owner_email: project.owner.email,
      can_delete: project.admin?(current_user) || current_project_membership&.admin? || false,
      share_usage_with_insights: project.share_usage_with_insights?,
      insights_connection_configured: project.insights_connection_configured?,
      insights_connection_token_last_used_at: project.insights_connection_token_last_used_at&.iso8601,
      can_manage_insights_sharing: can_manage_insights_sharing?,
      # Present only right after regeneration — shown once, never persisted.
      insights_connection_token: session.delete(:insights_connection_token_plaintext)
    }
  end
end
