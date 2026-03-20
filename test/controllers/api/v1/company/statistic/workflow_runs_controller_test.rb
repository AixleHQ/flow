# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Statistic::WorkflowRunsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @admin)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)
  end

  # ====== SHOW Tests ======

  test "#show returns 200 for company admin" do
    sign_in @admin

    get :show

    assert_response :success
  end

  test "#show returns 200 for company employee" do
    sign_in @employee

    get :show

    assert_response :success
  end

  test "#show requires authentication" do
    get :show

    assert_response :unauthorized
  end

  test "#show returns all expected stat fields" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json.key?("completed") }
    assert { json.key?("in_progress") }
    assert { json.key?("failed") }
    assert { json.key?("queued") }
    assert { json.key?("total") }
  end

  test "#show returns integer values for all fields" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    %w[completed in_progress failed queued total].each do |field|
      assert { json[field].is_a?(Integer) }
    end
  end

  test "#show counts only workflow runs belonging to current company" do
    create(:workflow_run, :completed, project: @project, user: @admin)
    create(:workflow_run, :running, project: @project, user: @admin)

    other_project = create(:project, company: @other_company, owner: @other_admin)
    create(:workflow_run, :completed, project: other_project, user: @other_admin)

    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json["total"] == 2 }
    assert { json["completed"] == 1 }
    assert { json["in_progress"] == 1 }
  end
end
