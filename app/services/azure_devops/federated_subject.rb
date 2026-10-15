# frozen_string_literal: true

module AzureDevops
  # The `sub` claim of the assertion Flow signs for one company, and the value a
  # customer enters in the federated credential of their own Entra app.
  #
  # One subject per company: the company is the unit that holds an installation,
  # and one credential then serves every Azure DevOps organization that app
  # reaches. It is built only from the company's immutable public id, never from
  # a name or slug, so nothing a user can type reaches it. Entra matches it
  # exactly and case-sensitively, with no wildcards.
  module FederatedSubject
    PREFIX = "aixle:company:"

    def self.for(company)
      raise ArgumentError, "company has no public id" if company&.public_id.blank?

      "#{PREFIX}#{company.public_id}"
    end
  end
end
