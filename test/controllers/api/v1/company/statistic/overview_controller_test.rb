# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Statistic::OverviewControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
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

  test "#show returns all expected counter fields" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json.key?("sessions_launched") }
    assert { json.key?("total_spend_cents") }
    assert { json.key?("workflows_count") }
    assert { json.key?("board_tasks_count") }
    assert { json.key?("users_count") }
    assert { json.key?("agents_count") }
    assert { json.key?("projects_count") }
  end

  test "#show returns integer values for all counters" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    %w[sessions_launched total_spend_cents workflows_count board_tasks_count users_count agents_count projects_count].each do |field|
      assert { json[field].is_a?(Integer) }
    end
  end

  test "#show counts only data belonging to current company" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json["users_count"] == @company.users.count }
    assert { json["projects_count"] == @company.projects.count }
  end
end
