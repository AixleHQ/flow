# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::WorkflowsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin)
  end

  test "#index returns merged workflows" do
    sign_in @admin
    create(:workflow, name: "ci", scope: @company)
    create(:workflow, name: "deploy", scope: @project)

    get :index, params: { project_id: @project.id }
    assert_response :success
    body = response.parsed_body
    names = body["items"].map { |w| w["name"] }
    assert_includes names, "ci"
    assert_includes names, "deploy"
  end

  test "#show returns workflow from merged scope" do
    sign_in @admin
    wf = create(:workflow, scope: @company)

    get :show, params: { project_id: @project.id, id: wf.id }
    assert_response :success
    body = response.parsed_body
    assert_equal wf.name, body["data"]["name"]
  end

  test "#create creates project-scoped workflow" do
    sign_in @admin
    post :create, params: { project_id: @project.id, workflow: { name: "proj-wf", description: "test" } }
    assert_response :created
    assert_equal "Project", Workflow.last.scope_type
    assert_equal @project.id, Workflow.last.scope_id
  end

  test "#update modifies project workflow" do
    sign_in @admin
    wf = create(:workflow, scope: @project)

    patch :update, params: { project_id: @project.id, id: wf.id, workflow: { description: "updated" } }
    assert_response :success
    assert_equal "updated", wf.reload.description
  end

  test "#destroy soft deletes project workflow" do
    sign_in @admin
    wf = create(:workflow, scope: @project)

    delete :destroy, params: { project_id: @project.id, id: wf.id }
    assert_response :no_content
    assert_not_nil wf.reload.deleted_at
  end

  test "non-member cannot access" do
    other_user = create(:user, :employee, company: @company)
    sign_in other_user

    get :index, params: { project_id: @project.id }
    assert_response :forbidden
  end

  test "collaborator can access" do
    collaborator = create(:user, :employee, company: @company)
    @project.add_collaborator(collaborator)
    sign_in collaborator

    get :index, params: { project_id: @project.id }
    assert_response :success
  end
end
