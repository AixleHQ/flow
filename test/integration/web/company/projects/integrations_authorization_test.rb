# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::IntegrationsController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::IntegrationsPolicy):
#   index?                                   => project_accessible?   (read)
#   create? / destroy? / slack_oauth_start?  => manage_integrations?  (write)
#     manage_integrations? = project_writable? && (current_user.admin? || project_owner?)
#
# DIVERGENCE from the generic project-write preset: writes require admin OR the
# project owner, so the employee *collaborator* — writable in the generic sense —
# is DENIED here alongside the read-only viewer. Only the owner and a company
# admin may manage integrations, hence the custom MANAGE matrix below instead of
# assert_project_write. Non-members are still scoped out to 404 before the policy.
#
# Allowed-write response shapes (no vendor stubbing — every real provider path in
# #create hits an external API, so we exercise the only vendor-free branches):
#   slack_oauth_start -> 302 redirect to Slack's consent URL, no flash alert
#                        (default :allowed_write web shape: redirect + nil alert).
#   create (unsupported provider) -> 302 redirect carrying flash[:alert]
#     "Unsupported provider: ..." — a deterministic body-level guard that proves
#     authorization already passed (denied roles never reach the body). Because
#     that alert is NOT the authz denial, we assert it with allowed_status: :redirect
#     to skip the default "no alert" check.
#   destroy -> 302 redirect with flash[:notice] (not :alert), so the default holds.
class Web::Company::Projects::IntegrationsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  # Writes are admin-or-owner (manage_integrations?): collaborator + viewer denied,
  # non-members scoped out to 404 before the policy runs.
  MANAGE = {
    owner: :allowed_write, admin: :allowed_write,
    collaborator: :denied, viewer: :denied,
    stranger: :not_found, foreign_admin: :not_found
  }.freeze

  setup do
    setup_project_authz_personas
    @integration = create(:integration, project: @project, company: @company, connected_by: @owner)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_integrations_path(@project) }
  end

  test "slack_oauth_start is admin-or-owner (redirects to Slack; collaborator/viewer denied)" do
    assert_role_matrix(MANAGE, transport: :web) do
      get slack_oauth_start_company_project_integrations_path(@project)
    end
  end

  # An unsupported provider hits the nil-integration branch => 302 + a non-authz
  # alert, proving the allowed role passed authorization and reached the body.
  test "create is admin-or-owner (collaborator/viewer denied)" do
    assert_role_matrix(MANAGE, transport: :web, allowed_status: :redirect) do
      post company_project_integrations_path(@project), params: { provider: "unsupported" }
    end
  end

  # destroy mutates, so build a throwaway integration per allowed-role iteration.
  test "destroy is admin-or-owner (collaborator/viewer denied)" do
    assert_role_matrix(MANAGE, transport: :web) do
      delete company_project_integration_path(
        @project, create(:integration, project: @project, company: @company, connected_by: @owner)
      )
    end
  end
end
