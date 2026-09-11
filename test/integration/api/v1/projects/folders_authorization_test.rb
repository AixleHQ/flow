# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API project-folders endpoints, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::FoldersPolicy < Api::V1::ApplicationPolicy):
#   writes (create/relocate/destroy) => project_writable?
# Inaccessible project (stranger / foreign admin) => 404: current_project is
# resolved via Project.for_user(current_user).find(:project_id), which raises
# RecordNotFound before the policy runs. The viewer is a collaborator (so may
# read the project) but is read_only?, so writes are denied (403).
class Api::V1::Projects::FoldersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "create is a project write" do
    assert_project_write(transport: :api) do |role|
      post api_v1_project_folders_path(@project), params: { folder: { path: "dashboard-#{role}" } }, as: :json
    end
  end

  test "relocate is a project write" do
    assert_project_write(transport: :api) do |role|
      create(:folder, path: "to-rename-#{role}", scope: @project, created_by: @owner)
      patch api_v1_project_folders_relocate_path(@project),
            params: { from_path: "to-rename-#{role}", to_path: "renamed-#{role}" }, as: :json
    end
  end

  test "destroy is a project write" do
    assert_project_write(transport: :api) do |role|
      create(:folder, path: "to-delete-#{role}", scope: @project, created_by: @owner)
      delete api_v1_project_folders_path(@project), params: { path: "to-delete-#{role}" }, as: :json
    end
  end
end
