# frozen_string_literal: true

class Web::Company::Projects::SettingsController < Web::Company::Projects::ApplicationController
  def show
    render inertia: "Projects/Settings/SettingsPage", props: {
      project: settings_project_props,
      concurrency: concurrency_props
    }
  end

  # One save, all or nothing. A limit that does not fit the company budget
  # must not leave the name change committed behind it: the person is told the
  # settings were not saved, and that has to be true of all of them.
  def update
    errors = {}

    ActiveRecord::Base.transaction do
      errors.merge!(current_project.errors.to_hash) unless current_project.update(project_params)
      errors.merge!(apply_concurrency_limit) if params.key?(:concurrency)
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
      queue_enabled: SessionAdmissionPolicy.enabled?,
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
      can_delete: project.admin?(current_user) || current_project_membership&.admin? || false
    }
  end
end
