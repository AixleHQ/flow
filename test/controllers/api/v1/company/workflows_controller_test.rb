# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::WorkflowsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
  end

  test "#index returns company workflows for admin" do
    sign_in @admin
    create(:workflow, name: "ci", scope: @company)
    create(:workflow, name: "deploy", scope: @company)

    get :index
    assert_response :success
    body = response.parsed_body
    assert_equal 2, body["items"].size
  end

  test "#index excludes deleted workflows" do
    sign_in @admin
    wf = create(:workflow, scope: @company)
    wf.soft_delete!

    get :index
    assert_response :success
    body = response.parsed_body
    assert_equal 0, body["items"].size
  end

  test "#show returns workflow" do
    sign_in @admin
    wf = create(:workflow, scope: @company)

    get :show, params: { id: wf.id }
    assert_response :success
    body = response.parsed_body
    assert_equal wf.name, body["data"]["name"]
    assert_equal "company", body["data"]["scope_indicator"]
  end

  test "#create creates company workflow" do
    sign_in @admin
    assert_difference "Workflow.count" do
      post :create, params: { workflow: { name: "new-workflow", description: "desc" } }
    end
    assert_response :created
    body = response.parsed_body
    assert_equal "new-workflow", body["data"]["name"]
    assert_equal "Company", Workflow.last.scope_type
    assert_equal @company.id, Workflow.last.scope_id
  end

  test "#create returns 422 for duplicate name" do
    sign_in @admin
    create(:workflow, name: "deploy", scope: @company)
    post :create, params: { workflow: { name: "deploy" } }
    assert_response :unprocessable_entity
  end

  test "#update modifies workflow" do
    sign_in @admin
    wf = create(:workflow, scope: @company)

    patch :update, params: { id: wf.id, workflow: { name: "updated" } }
    assert_response :success
    assert_equal "updated", wf.reload.name
  end

  test "#destroy soft deletes workflow" do
    sign_in @admin
    wf = create(:workflow, scope: @company)

    assert_no_difference "Workflow.unscoped.count" do
      delete :destroy, params: { id: wf.id }
    end
    assert_response :no_content
    assert_not_nil wf.reload.deleted_at
  end

  test "employee cannot access" do
    sign_in @employee
    get :index
    assert_response :forbidden
  end
end
