# frozen_string_literal: true

module Analytics
  # The properties every event carries, client and server alike, so any insight
  # can be split by company, plan state or role. Company-level facts live on
  # events rather than on the person, because one person may belong to several
  # companies.
  module Context
    module_function

    def props(user:, company: nil, project: nil, via: nil)
      membership = company && user && CompanyMembership.find_by(user_id: user.id, company_id: company.id)
      {
        "company_id" => company&.id,
        "billing_status" => company&.billing_status,
        "managed" => company&.managed_by_aixle?,
        "user_role" => membership&.role&.to_s,
        "onboarding_state" => membership && ONBOARDING_STATES[membership.onboarding_state],
        "app_version" => Settings.app.version,
        "project_id" => project&.id,
        "via" => via,
        # Server events would otherwise be placed wherever our servers are.
        "$geoip_disable" => true,
        "$set_once" => { "signup_date" => signup_date(user) }
      }.compact
    end

    def signup_date(user) = user.created_at.to_date.iso8601
  end
end
