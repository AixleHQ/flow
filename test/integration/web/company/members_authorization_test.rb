# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the company-level MembersController, via
# the shared AuthorizationMatrix harness (docs/testing.md §2). No project scope —
# personas come from setup_company_authz_personas (only @admin is a company admin;
# @owner/@collaborator/@stranger are plain employees, @viewer is external).
#
# Policy (Web::Company::MembersPolicy < Web::Company::ApplicationPolicy):
#   index?   => true                                             (read; every signed-in member, incl. foreign admin -> own company)
#   create?  => admin?                                           (write; NOT scoped to a record, so a foreign admin creates in THEIR company -> allowed)
#   update?  => admin? && same_company? && not_changing_own_role? (write)
#   destroy? => admin? && same_company? && not_self?             (write)
#
# same_company?/not_self?/not_changing_own_role? call `target_user`
# (current_user.company.users.find(params[:id])). For a foreign admin, admin? is
# true so `&&` does NOT short-circuit; the scoped find misses this company's member
# and raises RecordNotFound INSIDE the policy -> 404 (show_exceptions=:rescuable).
# For non-admins, admin? is false and `&&` short-circuits before the find, so they
# get a plain policy denial (302 + alert), never a 404. This is exactly the
# admin-only contract (assert_company_admin_only) for update/destroy on a record.
class Web::Company::MembersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_company_authz_personas
    # Target of update: a same-company member that is never `self`.
    @member = create_member(:employee)
  end

  teardown { teardown_authz }

  # index? => true: allowed for every persona (foreign admin simply lists their own
  # company's users, not a denial).
  test "index is readable by every signed-in company member (incl. foreign admin)" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :allowed_read },
      transport: :web
    ) { get company_members_path }
  end

  # create? => admin?, unscoped: admin allowed here, and a foreign admin is allowed
  # too (the invite lands in their OWN company). Every non-admin is denied.
  test "create is admin-only; foreign admin creates within their own company" do
    assert_role_matrix(
      { admin: :allowed_write, foreign_admin: :allowed_write,
        owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied },
      transport: :web
    ) do
      post company_members_path,
           params: { user: { email: "invite-#{SecureRandom.hex(3)}@example.com", name: "Invitee" } }
    end
  end

  # update? => admin? && same_company? && ...: admin allowed on another member,
  # non-admins denied (302), foreign admin scoped out of this company's record (404).
  test "update: admin only; foreign admin scoped out of this company's member" do
    assert_company_admin_only(kind: :write) do
      patch company_member_path(@member), params: { user: { role: "admin" } }
    end
  end

  # not_changing_own_role? guard: an admin targeting self WITH a :role param is
  # denied (admin? and same_company? both pass, so this is a policy denial, not 404).
  test "update denies an admin changing their own role (not_changing_own_role guard)" do
    assert_role_matrix({ admin: :denied }, transport: :web) do
      patch company_member_path(@admin), params: { user: { role: "employee" } }
    end
  end

  # destroy? => admin? && same_company? && not_self?: admin allowed, non-admins
  # denied, foreign admin 404. destroy mutates, so build a throwaway same-company
  # member per role iteration (the foreign admin's scoped find still misses it -> 404).
  test "destroy: admin only; foreign admin scoped out of this company's member" do
    assert_company_admin_only(kind: :write) do
      delete company_member_path(create_member(:employee))
    end
  end

  # not_self? guard: an admin removing THEMSELVES is denied (self, so not_self? is
  # false -> policy denial, not 404).
  test "destroy denies an admin removing themselves (not_self guard)" do
    assert_role_matrix({ admin: :denied }, transport: :web) do
      delete company_member_path(@admin)
    end
  end
end
