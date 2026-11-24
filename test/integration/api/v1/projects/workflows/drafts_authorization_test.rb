# frozen_string_literal: true

require "test_helper"

# Policy (Api::V1::Projects::Workflows::DraftsPolicy): create?, changes?, apply?, destroy? => project_writable?
class Api::V1::Projects::Workflows::DraftsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
  end

  teardown { teardown_authz }

  def with_draft
    WorkflowDrafts.open!(@workflow, actor: Versions::Actor.system)
  end

  test "opening a draft is a project write" do
    assert_project_write(transport: :api) { post api_v1_project_workflow_draft_path(@project, @workflow), as: :json }
  end

  test "reading what a draft changes is a project write" do
    with_draft
    assert_project_write(transport: :api) { get changes_api_v1_project_workflow_draft_path(@project, @workflow), as: :json }
  end

  test "applying a draft is a project write" do
    assert_project_write(transport: :api) do
      with_draft
      post apply_api_v1_project_workflow_draft_path(@project, @workflow), as: :json
    end
  end

  test "discarding a draft is a project write" do
    assert_project_write(transport: :api) do
      with_draft
      delete api_v1_project_workflow_draft_path(@project, @workflow), as: :json
    end
  end
end
