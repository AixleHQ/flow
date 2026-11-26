# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::Workflows::StepsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @workflow = create(:workflow, scope: @project)
    sign_in_as(@owner)
  end

  test "a step is created and updated with the project's AWS roles" do
    integration = create(:integration, :aws_oidc, company: @company, project: @project)
    first, second = create_list(:aws_oidc_role, 2, integration: integration)

    post api_v1_project_workflow_steps_path(@project, @workflow),
         params: { step: { name: "Diagnose", awsOidcRoleIds: [ first.id ] } }, as: :json

    assert_response :created
    assert_equal [ first.id ], response.parsed_body["awsOidcRoleIds"]

    step = @workflow.steps.find(response.parsed_body["id"])
    patch api_v1_project_workflow_step_path(@project, @workflow, step),
          params: { step: { awsOidcRoleIds: [ second.id, first.id ] } }, as: :json

    assert_response :success
    assert_equal [ second.id, first.id ], step.reload.aws_oidc_role_ids
  end
end
