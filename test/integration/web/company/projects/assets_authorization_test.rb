# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped web Assets controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::AssetsPolicy):
#   index?    => project_accessible?  (read)
#   versions? => project_accessible?  (read)   -- routed only via the API subclass
#   download? => project_accessible?  (read)   -- routed only via the API subclass
#   create?   => project_writable?    (write)  -- routed only via the API subclass
#   destroy?  => project_writable?    (write)  -- routed only via the API subclass
#
# The *web* controller exposes ONLY `index`
# (config/routes.rb -> `resources :assets, only: %i[index]`, i.e.
# GET /company/projects/:project_id/assets). versions/download/create/destroy are
# reachable only through the API subclass (Api::V1::Projects::AssetsPolicy <
# Web::Company::Projects::AssetsPolicy), so this file exercises the single `index`
# read: owner/admin/collaborator/viewer are allowed (reads permit the read-only
# viewer), while stranger/foreign admin are scoped out of Project.for_user (404).
# The viewer's read-only write denial is covered by the API assets authz test.
# `index` renders from an empty asset scope, so no asset fixtures are required.
class Web::Company::Projects::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }
  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_assets_path(@project) }
  end
end
