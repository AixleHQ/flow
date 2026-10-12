# frozen_string_literal: true

class Web::Company::Projects::SettingsController < Web::Company::Projects::ApplicationController
  def show
    render inertia: "Projects/Settings/SettingsPage", props: {
      project: settings_project_props,
      concurrency: concurrency_props,
      ownership: ownership_props
    }
  end

  # One save, all or nothing. A limit that does not fit the company budget
  # must not leave the name change committed behind it: the person is told the
  # settings were not saved, and that has to be true of all of them.
  def update
    errors = {}

    ActiveRecord::Base.transaction do
      # The General form sends `project`; the Usage-sharing toggle submits on
      # its own with only `insights_sharing_enabled`. Touch the attributes only
      # when that form was the sender, so a lone toggle is not a missing-param.
      if params.key?(:project)
        errors.merge!(current_project.errors.to_hash) unless current_project.update(project_params)
      end
      errors.merge!(apply_concurrency_limit) if params.key?(:concurrency)
      errors.merge!(apply_insights_sharing) if params.key?(:insights_sharing_enabled)
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_back fallback_location: company_project_settings_path(current_project),
                    inertia: { errors: errors }
    else
      redirect_to company_project_settings_path(current_project), notice: "Project updated successfully"
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :preferred_artifacts_language, :state)
  end

  def settings_policy
    @settings_policy ||= Web::Company::Projects::SettingsPolicy.new(policy_context, current_project)
  end

  def concurrency_limit_record
    @concurrency_limit_record ||= SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: current_project.id)
  end

  # Returns the errors to report, empty when there was nothing to refuse. The
  # single-word key survives prop camelization unchanged, which a
  # `session_concurrency_limit` would not.
  def apply_concurrency_limit
    return { concurrency: "Only a company admin can change the session limit" } unless settings_policy.manage_concurrency?

    requested = params[:concurrency].to_s.strip

    # Cleared field means "no reservation of my own" — the project falls back to
    # the deployment default and stops holding part of its company's budget.
    if requested.empty?
      concurrency_limit_record&.destroy
      return {}
    end

    record = concurrency_limit_record ||
             SessionConcurrencyLimit.new(scope_type: "Project", scope_id: current_project.id)
    record.max_sessions = requested
    return {} if record.save

    { concurrency: record.errors[:max_sessions].to_sentence.presence || record.errors.full_messages.to_sentence }
  end

  # Returns the errors to report, empty when the flag was applied. Admin-only
  # (variant A): turning sharing ON is refused unless the company has an active
  # Insights connection, so a project never carries a meaningless `true` with
  # nothing to export to. Turning it OFF is always allowed.
  def apply_insights_sharing
    return { insights_sharing_enabled: "Only a company admin can change usage sharing" } unless settings_policy.manage_insights_sharing?

    wanted = ActiveModel::Type::Boolean.new.cast(params[:insights_sharing_enabled])

    if wanted && insights_connection.nil?
      return { insights_sharing_enabled: "Connect Aixle Insights for this company before sharing a project" }
    end

    current_project.update(insights_sharing_enabled: wanted)
    {}
  end

  # The company's active Insights connection, or nil. Memoized — the update
  # path and the props both ask.
  def insights_connection
    return @insights_connection if defined?(@insights_connection)

    @insights_connection = Integration.aixle_insights_for(current_company)
  end

  def concurrency_props
    budget = SessionConcurrencyAllocation.new(
      company_id: current_project.company_id, excluding: concurrency_limit_record&.id
    )
    headroom = budget.available

    {
      max_sessions: concurrency_limit_record&.max_sessions,
      default: SessionAdmissionPolicy.scope_default("Project"),
      company_limit: budget.company_limit,
      # What this project could be raised to right now. Nil means no limit.
      available: headroom,
      allocations: budget.breakdown,
      can_manage: settings_policy.manage_concurrency?
    }
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
      insights_sharing_enabled: project.insights_sharing_enabled?,
      # The toggle is meaningful only with a company connection; the page shows
      # it disabled with a hint when there is none.
      insights_connected: insights_connection.present?,
      can_manage_insights_sharing: settings_policy.manage_insights_sharing?
    }
  end
end
