# frozen_string_literal: true

class Web::Company::SettingsController < Web::Company::ApplicationController
  def show
    render inertia: "Company/Settings/SettingsPage", props: props
  end

  # One save, all or nothing, for the same reason the project's settings are:
  # a capacity change that is refused must not leave a rename committed behind
  # it, or "settings were not saved" is a lie about half of them.
  def update
    errors = {}

    ActiveRecord::Base.transaction do
      current_company.logo = nil if clear_logo?
      errors.merge!(current_company.errors.to_hash) unless current_company.update(company_params)
      errors.merge!(apply_capacity) if params.key?(:capacity)
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_back fallback_location: company_settings_path, inertia: { errors: errors }
    else
      redirect_to company_settings_path, notice: "Company settings updated"
    end
  end

  private

  def settings_policy
    @settings_policy ||= Web::Company::SettingsPolicy.new(policy_context, current_company)
  end

  def company_params
    return {} unless settings_policy.update?

    params.fetch(:company, {}).permit(:display_name, :logo, :primary_color, :secondary_color, :auto_accept_users)
  end

  # Shrine's remove_attachment plugin is not loaded, so clearing is explicit. A
  # logo that can be set and never unset is a trap: the wrong file is permanent.
  def clear_logo?
    settings_policy.update? && params.dig(:company, :remove_logo).to_s == "true"
  end

  def capacity_limit_record
    @capacity_limit_record ||= SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: current_company.id)
  end

  # The single-word key survives prop camelization unchanged, which a
  # `session_concurrency_limit` would not.
  def apply_capacity
    return { capacity: "Only this installation's administrator can change the session limit" } unless settings_policy.manage_capacity?

    requested = params[:capacity].to_s.strip

    if requested.empty?
      capacity_limit_record&.destroy
      return {}
    end

    record = capacity_limit_record ||
             SessionConcurrencyLimit.new(scope_type: "Company", scope_id: current_company.id)
    record.max_sessions = requested
    return {} if record.save

    { capacity: record.errors[:max_sessions].to_sentence.presence || record.errors.full_messages.to_sentence }
  end

  def props
    {
      company: company_props,
      capacity: capacity_props,
      can_manage: settings_policy.update?
    }
  end

  def company_props
    {
      name: current_company.name,
      display_name: current_company.display_name,
      email_domain: current_company.email_domain,
      logo_url: current_company.logo_url,
      primary_color: current_company.primary_color,
      secondary_color: current_company.secondary_color,
      auto_accept_users: current_company.auto_accept_users
    }
  end

  def capacity_props
    allocation = SessionConcurrencyAllocation.new(company_id: current_company.id)

    {
      max_sessions: capacity_limit_record&.max_sessions,
      available: allocation.available,
      reserved: allocation.allocated,
      allocations: allocation.breakdown,
      project_default: SessionAdmissionPolicy.scope_default("Project"),
      queue_enabled: SessionAdmissionPolicy.enabled?,
      can_manage: settings_policy.manage_capacity?
    }
  end
end
