# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::PaladBuilderControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin)

    # Create the Palad Builder system workflow (simulating seed)
    @builder_workflow = Workflow.find_or_create_by!(
      scope_type: "System", scope_id: 0, name: "Palad Builder"
    ) do |w|
      w.description = "System meta-workflow"
      w.config = {}
    end
    create(:step, workflow: @builder_workflow, name: "Gather Requirements", position: 1, instructions: "Gather reqs")
  end

  test "#start creates a workflow run" do
    sign_in @admin

    WorkflowService.expects(:start).with(
      workflow: @builder_workflow,
      project: @project,
      user: @admin,
      mode: :interactive,
      agent_runtime: nil
    ).returns(create(:workflow_run, workflow: @builder_workflow, project: @project, user: @admin))

    post :start, params: { project_id: @project.id }
    assert_response :created
  end

  test "#status returns builder runs for project" do
    sign_in @admin

    run = create(:workflow_run, workflow: @builder_workflow, project: @project, user: @admin)

    get :status, params: { project_id: @project.id }
    assert_response :success
    body = response.parsed_body
    ids = body["items"].map { |r| r["id"] }
    assert_includes ids, run.id
  end

  test "#status excludes runs from other projects" do
    sign_in @admin
    other_project = create(:project, company: @company, owner: @admin)
    create(:workflow_run, workflow: @builder_workflow, project: other_project, user: @admin)

    get :status, params: { project_id: @project.id }
    assert_response :success
    body = response.parsed_body
    assert_equal 0, body["items"].size
  end
end
