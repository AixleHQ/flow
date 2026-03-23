# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Workflows::StepsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin)
    @workflow = create(:workflow, scope: @project)
  end

  test "#index returns steps with sub_steps" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)
    create(:sub_step, step: step, position: 1, name: "SS1")

    get :index, params: { project_id: @project.id, workflow_id: @workflow.id }
    assert_response :success
    body = response.parsed_body
    assert_equal 1, body["items"].size
    assert_equal 1, body["items"][0]["sub_steps"].size
  end

  test "#show returns step" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)

    get :show, params: { project_id: @project.id, workflow_id: @workflow.id, id: step.id }
    assert_response :success
    body = response.parsed_body
    assert_equal step.name, body["data"]["name"]
  end

  test "#create creates step" do
    sign_in @admin
    assert_difference "Step.count" do
      post :create, params: {
        project_id: @project.id, workflow_id: @workflow.id,
        step: { name: "Build", position: 1, instructions: "Build the project" }
      }
    end
    assert_response :created
  end

  test "#create with nested sub_steps" do
    sign_in @admin
    post :create, params: {
      project_id: @project.id, workflow_id: @workflow.id,
      step: {
        name: "Build", position: 1,
        sub_steps_attributes: [
          { name: "SS1", position: 1 },
          { name: "SS2", position: 2 }
        ]
      }
    }
    assert_response :created
    assert_equal 2, Step.last.sub_steps.count
  end

  test "#update modifies step" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)

    patch :update, params: {
      project_id: @project.id, workflow_id: @workflow.id, id: step.id,
      step: { name: "Updated" }
    }
    assert_response :success
    assert_equal "Updated", step.reload.name
  end

  test "#destroy hard-deletes step when no step_runs" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)

    assert_difference "Step.count", -1 do
      delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: step.id }
    end
    assert_response :no_content
  end

  test "#destroy soft-deletes step when step_runs exist" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)
    workflow_run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    create(:step_run, workflow_run: workflow_run, step: step)

    assert_no_difference "Step.count" do
      delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: step.id }
    end
    assert_response :no_content
    assert_not_nil step.reload.deleted_at
  end

  test "#index excludes soft-deleted steps" do
    sign_in @admin
    active_step = create(:step, workflow: @workflow, position: 1)
    deleted_step = create(:step, workflow: @workflow, position: 2)
    deleted_step.soft_delete!

    get :index, params: { project_id: @project.id, workflow_id: @workflow.id }
    assert_response :success
    body = response.parsed_body
    step_ids = body["items"].map { |s| s["id"] }
    assert_includes step_ids, active_step.id
    assert_not_includes step_ids, deleted_step.id
  end

  test "#reorder updates positions" do
    sign_in @admin
    s1 = create(:step, workflow: @workflow, position: 1)
    s2 = create(:step, workflow: @workflow, position: 2)

    patch :reorder, params: {
      project_id: @project.id, workflow_id: @workflow.id,
      positions: { s1.id.to_s => 2, s2.id.to_s => 1 }
    }
    assert_response :ok
    assert_equal 2, s1.reload.position
    assert_equal 1, s2.reload.position
  end

  test "#update with _destroy: true hard-deletes sub_step when no sub_step_runs" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)
    sub_step = create(:sub_step, step: step, position: 1, name: "ToDelete")

    patch :update, params: {
      project_id: @project.id, workflow_id: @workflow.id, id: step.id,
      step: { sub_steps_attributes: [ { id: sub_step.id, _destroy: true } ] }
    }
    assert_response :success
    assert_not SubStep.exists?(sub_step.id)
  end

  test "#update with _destroy: true soft-deletes sub_step when sub_step_runs exist" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)
    sub_step = create(:sub_step, step: step, position: 1, name: "ToSoftDelete")
    workflow_run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)
    create(:sub_step_run, sub_step: sub_step, step_run: step_run)

    patch :update, params: {
      project_id: @project.id, workflow_id: @workflow.id, id: step.id,
      step: { sub_steps_attributes: [ { id: sub_step.id, _destroy: true } ] }
    }
    assert_response :success
    assert_not_nil sub_step.reload.deleted_at
  end

  test "#update soft-deleted sub_step is excluded from response" do
    sign_in @admin
    step = create(:step, workflow: @workflow, position: 1)
    sub_step = create(:sub_step, step: step, position: 1, name: "ToSoftDelete")
    workflow_run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)
    create(:sub_step_run, sub_step: sub_step, step_run: step_run)

    patch :update, params: {
      project_id: @project.id, workflow_id: @workflow.id, id: step.id,
      step: { sub_steps_attributes: [ { id: sub_step.id, _destroy: true } ] }
    }
    assert_response :success
    body = response.parsed_body
    sub_step_ids = body["data"]["sub_steps"].map { |ss| ss["id"] }
    assert_not_includes sub_step_ids, sub_step.id
  end

  test "#destroy returns error when another step depends on it" do
    sign_in @admin
    step_a = create(:step, workflow: @workflow, position: 1)
    step_b = create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [ step_a.id ])

    assert_no_difference "Step.count" do
      delete :destroy, params: { project_id: @project.id, workflow_id: @workflow.id, id: step_a.id }
    end
    assert_response :unprocessable_entity
    assert_nil step_a.reload.deleted_at
  end

  test "non-member cannot access" do
    other_user = create(:user, :employee, company: @company)
    sign_in other_user

    get :index, params: { project_id: @project.id, workflow_id: @workflow.id }
    assert_response :forbidden
  end
end
