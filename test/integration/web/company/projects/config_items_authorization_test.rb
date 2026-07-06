# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped web ConfigItems
# controller, via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::ConfigItemsPolicy < Web::Company::ApplicationPolicy):
#   index?                       => project_accessible?  (read)
#   create? / update? / destroy? => project_writable?    (write)
#
# project_accessible? => project.accessible_by?(current_user) (owner, collaborator,
# or a same-company admin); project_writable? adds !current_user.read_only? (so the
# viewer collaborator is accessible-but-not-writable => denied on writes). A stranger
# / foreign admin is scoped out of Project.for_user => RecordNotFound => 404 before
# the policy runs.
#
# A project has no auto-created config item, so @item (project-scoped) is built here
# for the update path; destroy builds a throwaway record per iteration. Both are
# visible via ConfigItem.visible_for_project, so allowed roles find them (302, not 404).
class Web::Company::Projects::ConfigItemsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @item = create(:config_item, scope: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_config_items_path(@project) }
  end

  # Unique name per iteration: name is unique within {scope_type, scope_id}, and the
  # allowed roles (owner/admin/collaborator) each create in the same project in one test.
  test "create is a project write" do
    assert_project_write do
      post company_project_config_items_path(@project),
           params: { config_item: { name: "VAR_#{SecureRandom.hex(3)}", value: "v", item_type: "variable" } }
    end
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_config_item_path(@project, @item), params: { config_item: { value: "updated" } }
    end
  end

  # destroy mutates, so build a throwaway item per role iteration.
  test "destroy is a project write" do
    assert_project_write do
      delete company_project_config_item_path(@project, create(:config_item, scope: @project))
    end
  end
end
