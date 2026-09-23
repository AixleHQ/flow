# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the company settings screen.
#
# Policy (Web::Company::SettingsPolicy < Web::Company::ApplicationPolicy):
#   show?            => true      (every signed-in member reads their own company)
#   update?          => admin?    (unscoped, so a foreign admin writes in THEIR company)
#   manage_capacity? => admin? && Deployment.customer_owns_capacity?
class Web::Company::SettingsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_company_authz_personas }
  teardown { teardown_authz }

  test "show is readable by every signed-in company member" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :allowed_read },
      transport: :web
    ) { get company_settings_path }
  end

  # update? is not scoped to a record, so a foreign admin writing lands in their
  # own company and is allowed — the same shape as MembersController#create.
  test "update is admin-only; a foreign admin writes within their own company" do
    assert_role_matrix(
      { admin: :allowed_write, foreign_admin: :allowed_write,
        owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied },
      transport: :web
    ) do
      patch company_settings_path, params: { company: { display_name: "Renamed" } }
    end
  end
end
