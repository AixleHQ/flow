# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Statistic::RecentActivityControllerTest < ActionController::TestCase
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

  test "#show returns 200 for company employee with project access" do
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
    assert { json.key?("activities") }
    assert { json.key?("meta") }
  end

  test "#show returns expected meta fields" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
    meta = response.parsed_body["meta"]
    %w[total page per_page].each do |field|
      assert { meta.key?(field) }
    end
  end

  test "#show returns activities as an array" do
    sign_in @admin

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert { response.parsed_body["activities"].is_a?(Array) }
  end
end
