# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::WorkflowRunsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, name: "wfrun-co-#{SecureRandom.hex(4)}")
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin, name: "wfrun-proj-#{SecureRandom.hex(4)}")
    @workflow = create(:workflow, scope: @company, name: "wfrun-wf-#{SecureRandom.hex(4)}")
    @step = create(:step, workflow: @workflow, position: 1)
  end

  test "#index returns workflow runs for project" do
    sign_in @admin
    create(:workflow_run, project: @project, workflow: @workflow, user: @admin)
    create(:workflow_run, project: @project, workflow: @workflow, user: @admin)

    get :index, params: { project_id: @project.id }
    assert_response :success
    body = response.parsed_body
    assert_equal 2, body["items"].size
  end

  test "#show returns a single workflow run" do
    sign_in @admin
    run = create(:workflow_run, project: @project, workflow: @workflow, user: @admin)

    get :show, params: { project_id: @project.id, id: run.id }
    assert_response :success
    body = response.parsed_body
    data = body["data"] || body["workflow_run"] || body
    assert_equal run.id, data["id"]
    assert_equal "pending", data["state"]
  end

  test "#create creates a workflow run with interactive mode" do
    sign_in @admin
    mock_workflow_execution_start

    assert_difference "WorkflowRun.count", 1 do
      post :create, params: {
        project_id: @project.id,
        workflow_run: {
          workflow_id: @workflow.id,
          mode: "interactive"
        }
      }
    end

    assert_response :created
    body = response.parsed_body
    data = body["data"] || body["workflow_run"] || body
    assert_equal "interactive", data["mode"]
    assert_equal "pending", data["state"]
    assert_equal @workflow.id, data["workflow_id"]
    assert_equal @project.id, data["project_id"]
  end

  test "#create creates first step run" do
    sign_in @admin
    mock_workflow_execution_start

    post :create, params: {
      project_id: @project.id,
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "interactive"
      }
    }

    assert_response :created
    run = WorkflowRun.last
    assert_equal 1, run.step_runs.count
    assert_equal @step.id, run.step_runs.first.step_id
  end

  test "#create rejects non_interactive mode when steps require interaction" do
    sign_in @admin
    @step.update!(allow_non_interactive: false)

    post :create, params: {
      project_id: @project.id,
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "non_interactive"
      }
    }

    assert_response :unprocessable_entity
  end

  test "#create allows non_interactive mode when all steps support it" do
    sign_in @admin
    @step.update!(allow_non_interactive: true)
    mock_workflow_execution_start

    post :create, params: {
      project_id: @project.id,
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "non_interactive"
      }
    }

    assert_response :created
    body = response.parsed_body
    data = body["data"] || body["workflow_run"] || body
    assert_equal "non_interactive", data["mode"]
  end

end
