# frozen_string_literal: true

FactoryBot.define do
  factory :identity_provider do
    kind { "oidc" }
    scope { "company" }
    company

    # Deployment-scoped providers are installation singletons, so a factory that
    # blindly created one would collide with IdentityProvider.deployment!. Use
    # the model method for those; this trait exists for the rare test that wants
    # an explicit, non-allowlisted deployment row.
    trait :deployment do
      scope { "deployment" }
      company { nil }
      kind { "magic_link" }
    end
  end
end
