# frozen_string_literal: true

module Auth
  # Gives a company an explicit policy row for every deployment-scoped provider.
  #
  # An absent row means DENIED (AD-4), so seeding is what keeps a newly created
  # company usable and keeps "no row" from being an ambiguous default. New rows
  # default to enabled: restricting is the admin's deliberate act, never a
  # side effect of creating a company.
  module CompanyPolicySeeder
    module_function

    def seed!(company)
      Auth::DeploymentProviders.ensure_all!.map do |provider|
        CompanyAuthPolicy.find_or_create_by!(company: company, identity_provider: provider) do |policy|
          policy.enabled = true
        end
      end
    end
  end
end
