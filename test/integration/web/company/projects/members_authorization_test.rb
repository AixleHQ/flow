# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::MembersController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::MembersPolicy):
#   index?   => project_accessible?  (read)
#   create?  => project_writable?    (write)
#   destroy? => project_writable?    (write)
# where project_writable? == project_accessible? && !current_user.read_only?
# (read_only? == viewer). Strangers / foreign-company users fall outside
# Project.for_user, so the scoped `.find` raises RecordNotFound => 404 before the
# policy runs. Writes create/destroy a throwaway member per allowed role so
# shared state stays deterministic; destroy's target is a fresh user (never the
# actor), so the self-removal guard in the action body — which would redirect
# WITH an alert and break the allowed-write contract — is never tripped.
class Web::Company::Projects::MembersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_members_path(@project) }
  end

  test "create is a project write" do
    assert_project_write do
      target = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
      post company_project_members_path(@project), params: { collaborator: { user_id: target.id } }
    end
  end

  # destroy mutates, so add a throwaway collaborator per role iteration; it is a
  # fresh user (never the actor), so the action's self-removal guard never fires.
  test "destroy is a project write" do
    assert_project_write do
      target = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
      @project.add_collaborator(target)
      delete company_project_member_path(@project, target)
    end
  end
end
