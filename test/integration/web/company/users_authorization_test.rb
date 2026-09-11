# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the organization-visible member profile
# (/user/:id), via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::UsersPolicy < Web::Company::ApplicationPolicy):
#   show? => true
#
# The gate that matters here is not the policy but the SCOPE: the controller
# resolves the subject through current_company's memberships, so a foreign admin
# passes show? and then misses the record — RecordNotFound, which
# show_exceptions=:rescuable turns into a 404. That is the contract the page
# depends on: "not a member of this company" must read as "no such page", never
# as "not allowed", which would confirm the account exists.
class Web::Company::UsersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_company_authz_personas
    # The subject of the profile: a same-company member nobody in the matrix is.
    @subject = create_member(:employee)
  end

  teardown { teardown_authz }

  test "show is readable by every member of the company, and 404s for a foreign admin" do
    assert_role_matrix(
      { admin: :allowed_read, owner: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :not_found },
      transport: :web
    ) { get user_path(@subject) }
  end
end
