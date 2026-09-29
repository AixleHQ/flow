# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::WorkflowRunAssetsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @owner)
    sign_in_as(@owner)
  end

  test "lists a shared output with its public link" do
    output = create(:workflow_run_asset, workflow_run: @run)
    output.share!

    get api_v1_project_workflow_run_workflow_run_assets_path(@project, @run), as: :json

    assert_response :success
    assert_equal output.share_url, response.parsed_body.first["shareUrl"]
  end

  test "unshare stops a public link working" do
    output = create(:workflow_run_asset, workflow_run: @run)
    token = output.share!

    delete share_api_v1_project_workflow_run_workflow_run_asset_path(@project, @run, output), as: :json

    assert_response :success
    assert_nil response.parsed_body["shareUrl"]
    assert_nil PubliclyShareable.find_shared(token)
  end
end
