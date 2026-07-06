# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the company-level (NOT project-scoped)
# Assets JSON API, via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Company::AssetsPolicy < Api::V1::ApplicationPolicy):
#   download? => true         (read)  — EVERY authenticated company member, incl.
#                                       the read-only viewer, may read.
#   create?   => !read_only?  (write) — viewer denied; all non-viewers allowed.
#   destroy?  => !read_only?  (write) — viewer denied; all non-viewers allowed.
#
# This is NOT admin-only: the gate is `read_only?`, not `admin?`, so owner /
# admin / plain employee / stranger are treated identically (all non-read-only),
# which is why the admin-only preset does not fit and the escape hatch is used.
# Record scoping lives in the controller (`current_company.assets.find`,
# current_company == current_user.company), not the policy. Consequences per
# action drive the matrices below:
#   * download: authz always passes; a same-company actor is redirected (302) to
#     the file url, a foreign-company admin is scoped out => 404.
#   * create: has no record to scope, so a foreign admin creates in their OWN
#     company (allowed). Allowed actors clear authz and reach
#     params.require(:asset) => ParameterMissing => 400 (a 400, not 403, proves
#     the policy permitted them without building a valid multipart upload body).
#   * destroy: a foreign admin clears authz (!read_only?) but the cross-company
#     scoped `.find` raises RecordNotFound => 404; same-company non-viewers 200.
class Api::V1::Company::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_company_authz_personas
    # Downloadable asset (version with an attached file) owned by @company.
    @asset = create(:asset, :with_company_scope, scope: @company, created_by: @owner)
    create(:asset_version, :with_file, asset: @asset, uploaded_by: @owner)
  end

  teardown { teardown_authz }

  # download? == true: every same-company member (including the read-only viewer)
  # clears authz and is redirected (302) to the file url; the foreign-company
  # admin is scoped out of this company's rows => 404.
  test "download: any same-company member reads (302); foreign admin scoped out (404)" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :allowed_read, foreign_admin: :not_found },
      transport: :api, allowed_status: :redirect
    ) { get download_api_v1_company_asset_path(@asset) }
  end

  # create? == !read_only?: viewer denied (403) before any param parsing; every
  # non-viewer (incl. the foreign admin, who would create in their own company)
  # clears authz and hits params.require(:asset) => 400. A 400 rather than 403 is
  # the evidence the policy permitted them — no valid upload payload needed.
  test "create: viewer forbidden; non-viewers clear authz (400 param-missing)" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        stranger: :allowed_write, foreign_admin: :allowed_write, viewer: :denied },
      transport: :api, allowed_status: :bad_request
    ) { post api_v1_company_assets_path, as: :json }
  end

  # destroy? == !read_only?: viewer denied (403) before the record loads;
  # same-company non-viewers soft-delete (200); the foreign admin clears authz
  # but is scoped out of this company's asset => 404. destroy mutates, so build a
  # throwaway asset per role iteration.
  test "destroy: viewer forbidden; same-company non-viewers 200; foreign admin 404" do
    assert_role_matrix(
      { owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
        stranger: :allowed_write, viewer: :denied, foreign_admin: :not_found },
      transport: :api
    ) do
      delete api_v1_company_asset_path(create(:asset, :with_company_scope, scope: @company, created_by: @owner))
    end
  end
end
