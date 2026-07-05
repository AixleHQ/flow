# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Api::V1::AssetsController, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# These are the TOP-LEVEL direct-upload endpoints (collection routes, neither
# project- nor company-scoped):
#   presign (GET  /api/v1/assets/presign) -> presign? == !read_only?   (read)
#   upload  (POST /api/v1/assets/upload)  -> upload?  == !read_only?   (write)
#
# Policy (Api::V1::AssetsPolicy < Api::V1::ApplicationPolicy) gates PURELY on the
# read-only (viewer) predicate — it never loads a record and never touches a
# project or company. So this is a GLOBAL endpoint: the ONLY denial axis is
# read-only. Unlike the project/company presets, a same-company `stranger` and a
# foreign-company admin are NOT scoped out to 404 — with no record to scope, they
# are PERMITTED (caching an upload is only a precursor to a write; promotion to a
# real, scoped asset is authorized separately downstream). Hence neither
# assert_project_* nor assert_company_admin_only fits; the matrix is spelled out
# via assert_role_matrix: every non-read-only role is allowed, the viewer is 403.
#
# Denial (Api::V1::ApplicationController): Pundit::NotAuthorizedError => 403
# {error:"Not authorized"}, backed by the deny_read_only_mutation! verb backstop.
# No record is loaded, so there is intentionally NO 404 row here.
#
# `upload` sends a real multipart body (fixture_file_upload): in the test env the
# :cache store is Shrine::Storage::Memory, so an allowed role caches the file and
# the controller returns 204 (a clean 2xx) — no vendor/Shrine stubbing. An empty
# body would instead raise JSON::ParserError inside the action (not an HTTP
# status), so a valid body is what lets the harness assert on the real response.
class Api::V1::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_company_authz_personas }
  teardown { teardown_authz }

  test "presign: permitted for every non-read-only role; viewer (read-only) => 403" do
    assert_role_matrix(non_read_only_matrix(:allowed_read), transport: :api) do
      get presign_api_v1_assets_path
    end
  end

  test "upload: permitted for every non-read-only role; viewer (read-only) => 403" do
    assert_role_matrix(non_read_only_matrix(:allowed_write), transport: :api) do
      post upload_api_v1_assets_path,
           params: { file: fixture_file_upload("test_file.txt", "text/plain") }
    end
  end

  private

  # Global read-only-only gate: only the viewer (read_only?) is denied; every
  # other persona is permitted because there is no record/project/company scope
  # to fence strangers or foreign admins out.
  def non_read_only_matrix(access)
    {
      owner: access, admin: access, collaborator: access,
      stranger: access, foreign_admin: access,
      viewer: :denied
    }
  end
end
