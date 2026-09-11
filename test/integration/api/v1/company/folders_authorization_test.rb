# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the company-level (NOT project-scoped)
# Folders JSON API, via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Company::FoldersPolicy < Api::V1::ApplicationPolicy):
#   create? / relocate? / destroy? => !read_only? — viewer denied; every
#   non-viewer (including a foreign-company admin, who acts in THEIR OWN
#   company) is allowed. Not admin-only, so the generic role-matrix escape
#   hatch is used rather than assert_company_admin_only, mirroring
#   Api::V1::Company::AssetsAuthorizationTest.
class Api::V1::Company::FoldersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_company_authz_personas }

  teardown { teardown_authz }

  test "create: viewer forbidden; every other role (incl. foreign admin, in their own company) succeeds" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        stranger: :allowed_write, foreign_admin: :allowed_write, viewer: :denied },
      transport: :api
    ) do |role|
      post api_v1_company_folders_path, params: { folder: { path: "dashboard-#{role}" } }, as: :json
    end
  end

  test "relocate: viewer forbidden; same-company non-viewers succeed; foreign admin 404 (nothing to relocate in their company)" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        stranger: :allowed_write, viewer: :denied, foreign_admin: :not_found },
      transport: :api
    ) do |role|
      create(:folder, path: "to-rename-#{role}", scope: @company, created_by: @owner)
      patch api_v1_company_folders_relocate_path,
            params: { from_path: "to-rename-#{role}", to_path: "renamed-#{role}" }, as: :json
    end
  end

  test "destroy: viewer forbidden; same-company non-viewers succeed; foreign admin 404" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        stranger: :allowed_write, viewer: :denied, foreign_admin: :not_found },
      transport: :api
    ) do |role|
      create(:folder, path: "to-delete-#{role}", scope: @company, created_by: @owner)
      delete api_v1_company_folders_path, params: { path: "to-delete-#{role}" }, as: :json
    end
  end
end
