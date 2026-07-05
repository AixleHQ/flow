# frozen_string_literal: true

require "test_helper"

# Authorization matrix for the company-level Assets controller (admin-only), via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Only ONE action is routed to Web::Company::AssetsController
# (`rails routes -c Web::Company::AssetsController` maps just #index):
#   index (GET /company/assets) => current_user.admin?   (read)
# The policy also declares create?/destroy?/versions?/download? (all admin?), but
# those are served by OTHER controllers (Web::Company::Projects::AssetsController,
# Api::V1::Company::AssetsController, ...) — none are routed here.
#
# Chain: Web::Company::AssetsPolicy < Web::Company::ApplicationPolicy < ApplicationPolicy.
# Context = BaseContext (no project, no record); dynamic_authorize! resolves
# index -> AssetsPolicy#index?. The action reads current_company.assets
# (== current_user.company.assets) with no cross-company `.find` on the plain
# index request, so there is nothing to scope a foreign admin out of: any admin —
# own or foreign — passes and renders THEIR OWN (empty) assets => 200, while every
# non-admin persona is denied => 302 + "You are not authorized to perform this action."
class Web::Company::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_company_authz_personas }

  teardown { teardown_authz }

  test "index: admin only (foreign admin sees their own empty list)" do
    assert_company_admin_only(kind: :read) { get company_assets_path }
  end
end
