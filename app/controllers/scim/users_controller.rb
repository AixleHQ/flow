# frozen_string_literal: true

# SCIM 2.0 Users for one company's directory (CAP-6, AD-10).
#
# The resource is a CompanyMembership, not a User: a person can belong to several
# companies, and a customer's directory owns membership of THEIR company only.
# Every write goes through the same AASM events the UI uses, so a deprovisioning
# produces the same audited transition as a human clicking "remove".
#
# SCIM never writes user_identities. A provisioned person has no identity row
# until their first real sign-in creates one (AD-3, AD-10) — which is what makes
# provisioning-before-first-login coherent instead of a second identity
# authority.
class Scim::UsersController < Scimitar::ActiveRecordBackedResourcesController
  # Token-authenticated machine API, exactly like the api/v1 tree: a customer's
  # directory sends a bearer token and no CSRF token, because it is not a
  # browser. Without this every SCIM write answers "Can't verify CSRF token
  # authenticity" — and the test environment disables forgery protection, so a
  # request test cannot catch it.
  skip_before_action :verify_authenticity_token, raise: false

  protected

  def storage_class
    CompanyMembership
  end

  def storage_scope
    company = ScimCurrent.company
    raise Scimitar::AuthenticationError if company.nil?

    CompanyMembership.where(company: company).where.not(state: "revoked")
  end
end
