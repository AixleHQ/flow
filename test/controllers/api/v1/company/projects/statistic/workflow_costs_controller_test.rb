# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Statistic::WorkflowCostsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @admin)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)
  end

  # ====== Authentication ======

  test "#show returns 401 when unauthenticated" do
    get :show, params: { project_id: @project.id }

    assert_response :unauthorized
  end

  # ====== Authorization ======

  test "#show returns 200 for company admin" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
  end

  test "#show returns 200 for company employee" do
    @project.add_collaborator(@employee)
    sign_in @employee

    get :show, params: { project_id: @project.id }

    assert_response :success
  end

  test "#show returns 404 for admin of another company" do
    sign_in @other_admin

    get :show, params: { project_id: @project.id }

    assert_response :not_found
  end

  # ====== JSON shape ======

  test "#show returns expected top-level keys" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert { json.key?("workflows") }
    assert { json.key?("timeSeries") }
    assert { json.key?("totals") }
  end

  test "#show returns expected totals fields" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    totals = json["totals"]
    %w[totalCostCents inputTokens outputTokens totalTokens workflowCount avgCostCentsPerWorkflow].each do |field|
      assert { totals.key?(field) }
    end
  end

  test "#show returns arrays for workflows and timeSeries" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert { json["workflows"].is_a?(Array) }
    assert { json["timeSeries"].is_a?(Array) }
  end

  # ====== Scope param ======

  test "#show accepts scope=project" do
    sign_in @admin

    get :show, params: { project_id: @project.id, scope: "project" }

    assert_response :success
  end

  test "#show accepts scope=user" do
    sign_in @admin

    get :show, params: { project_id: @project.id, scope: "user" }

    assert_response :success
  end

  test "#show accepts scope=company" do
    sign_in @admin

    get :show, params: { project_id: @project.id, scope: "company" }

    assert_response :success
  end

  # ====== Period param ======

  test "#show accepts period=7d" do
    sign_in @admin

    get :show, params: { project_id: @project.id, period: "7d" }

    assert_response :success
  end

  test "#show accepts period=30d" do
    sign_in @admin

    get :show, params: { project_id: @project.id, period: "30d" }

    assert_response :success
  end

  test "#show accepts period=90d" do
    sign_in @admin

    get :show, params: { project_id: @project.id, period: "90d" }

    assert_response :success
  end

  test "#show accepts period=1y" do
    sign_in @admin

    get :show, params: { project_id: @project.id, period: "1y" }

    assert_response :success
  end
end
