# frozen_string_literal: true

require "test_helper"

# Authorization matrix for the company-level Sessions::Artifacts controller, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Sessions::ArtifactsPolicy) is plain-permissive:
#   index?  => true
#   review? => true
# So the policy admits every persona; the real gate is record scoping in the
# controller (`company_sessions_scope`): a session is reachable by ANY member of
# the company that owns it (session.user in company.users OR session.project in
# company) and is scoped out (404) for a user of a different company. There is no
# read_only gate here, so the external viewer may review too — both actions are
# "any company member", not project- or admin-scoped.
class Web::Company::Sessions::ArtifactsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_company_authz_personas
    # A session owned by a company user: visible to every member of @company,
    # and scoped out (404) for the foreign-company admin.
    @session = create(:terminal_session, :agent_session, user: @owner)
    # created_by must be a company user: the :asset factory otherwise builds a
    # company-less user, which fails the "company must be present" validation.
    @artifact = create(:asset, terminal_session: @session, scope: @company,
                               created_by: @owner, status: "pending_review")
  end

  teardown { teardown_authz }

  # index renders any company session's artifacts; the foreign admin is scoped
  # out to 404 by `company_sessions_scope`.
  test "index is a company-member read" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :not_found },
      transport: :web
    ) do
      get company_session_artifacts_path(@session)
    end
  end

  # review persists artifact decisions. The policy is `true` (no read_only gate),
  # so every company member is allowed; the foreign admin is scoped out (404). A
  # one-key `decisions` body clears the `params.require(:decisions)` guard and
  # dismisses the artifact, yielding a clean 302 redirect for the allowed roles.
  test "review is a company-member write" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        viewer: :allowed_write, stranger: :allowed_write, foreign_admin: :not_found },
      transport: :web
    ) do
      post review_company_session_artifacts_path(@session),
           params: { decisions: { @artifact.id.to_s => "dismiss" } }
    end
  end
end
