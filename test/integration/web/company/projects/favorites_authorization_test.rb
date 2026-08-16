# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::FavoritesController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::FavoritesPolicy):
#   create?  => project_accessible?
#   destroy? => project_accessible?
#
# Deliberately NOT the usual read/write split: these are writes (302 redirect on
# success) that a read-only VIEWER is also allowed to make, because a favorite is
# the actor's own list ordering and changes nothing about the project. So the
# expected matrix is the read matrix's audience with the write transport
# contract. Strangers / foreign-company users fall outside Project.for_user, so
# the scoped `.find` raises RecordNotFound => 404 before the policy runs.
class Web::Company::Projects::FavoritesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  # Everyone who can see the project may star it — including the viewer.
  EXPECTATIONS = {
    owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write, viewer: :allowed_write,
    stranger: :not_found, foreign_admin: :not_found
  }.freeze

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "create is a write every role that can see the project may make" do
    assert_role_matrix(EXPECTATIONS, transport: :web) { post company_project_favorite_path(@project) }
  end

  # destroy mutates, so each allowed role stars the project first — the endpoint
  # is idempotent, but the assertion is about authorization, not the row count.
  test "destroy is a write every role that can see the project may make" do
    assert_role_matrix(EXPECTATIONS, transport: :web) do |role|
      user = user_for(role)
      ProjectFavorite.find_or_create_by!(user: user, project: @project) if @project.accessible_by?(user)

      delete company_project_favorite_path(@project)
    end
  end
end
