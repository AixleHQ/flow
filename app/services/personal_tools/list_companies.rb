# frozen_string_literal: true

module PersonalTools
  class ListCompanies < Base
    tool do
      display_name "List Companies"
      description "List the companies your Aixle account belongs to, with ids to use in other tools."
      audience :user
      tags :account
      read_only
      input_schema(type: "object", properties: {}, required: [])
    end

    def execute
      companies = [ user.company ].compact.map do |company|
        { id: company.id, name: company.name, slug: company.slug }
      end
      success(companies: companies)
    end
  end
end
