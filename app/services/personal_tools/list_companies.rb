# frozen_string_literal: true

module PersonalTools
  class ListCompanies < Base
    tool do
      display_name "List Companies"
      description "List the companies your Aixle account actively belongs to, with your role in each and ids to use in other tools."
      audience :user
      tags :account
      read_only
      input_schema(type: "object", properties: {}, required: [])
    end

    def execute
      companies = user.company_memberships.active.includes(:company).map do |membership|
        company = membership.company
        { id: company.id, name: company.name, slug: company.slug, role: membership.role.to_s }
      end
      success(companies: companies)
    end
  end
end
