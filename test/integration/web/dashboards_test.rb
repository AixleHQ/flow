# frozen_string_literal: true

require "test_helper"

class Web::DashboardsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, name: "Acme")
    @viewer = create(:user, :dashboard_viewer, :onboarding_completed, company: @company,
                                                                      password: AuthHelper::TEST_PASSWORD)
  end

  def admit_one_session_that_waited_five_minutes
    owner = create(:user, company: @company)
    project = create(:project, company: @company, owner: owner)
    pool = SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 4, policy_revision: 1)
    SessionAdmission.create!(terminal_session: create(:terminal_session, :agent_session, project: project, user: owner),
                             session_admission_pool: pool, created_at: Time.utc(2026, 10, 14, 9),
                             admitted_at: Time.utc(2026, 10, 14, 9, 5))
  end

  def island_in(body)
    Nokogiri::HTML(body).at_css("#admin-dashboard")
  end

  test "a dashboard viewer reads the admin's dashboard at /dashboard, and nothing of the admin's around it" do
    CompanyUsageHour.create!(company: @company, period_start: Time.utc(2026, 10, 14, 9), billing_class: "managed",
                             occupied_seconds: 1_800, computed_at: Time.utc(2026, 10, 14, 10, 10))
    sign_in_as(@viewer)

    get dashboard_path

    assert_response :success
    island = island_in(response.body)
    report = JSON.parse(island["data-report"])
    assert_equal [ "Acme" ], report["tenants"].pluck("name")
    assert_equal 1_800, report["days"].sole["occupiedSeconds"]
    assert_equal "/dashboard", island["data-base"]
    assert_nil island["data-company-records"]
    assert_empty Nokogiri::HTML(response.body).css("a[href^='/admin']")
  end

  test "the report is the admin's own, to the last figure" do
    CompanyUsageHour.create!(company: @company, period_start: Time.utc(2026, 10, 14, 9), billing_class: "managed",
                             occupied_seconds: 1_800, computed_at: Time.utc(2026, 10, 14, 10, 10))
    sign_in_as(create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD))
    get admin_dashboard_path
    admins = island_in(response.body)["data-report"]

    reset!
    sign_in_as(@viewer)
    get dashboard_path

    assert_equal admins, island_in(response.body)["data-report"]
  end

  test "the dashboard's queue figures are read from /dashboard too" do
    admit_one_session_that_waited_five_minutes
    sign_in_as(@viewer)

    get waits_dashboard_path(from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :success
    assert_equal [ { "companyId" => @company.id, "p95" => 300 } ], response.parsed_body

    get dashboard_company_path(@company, from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :success
    assert_equal [ 1, 1, 300 ], response.parsed_body["waits"].values_at("sessions", "waited", "p95")

    get hours_dashboard_company_path(@company, from: "2026-10-01", to: "2026-10-31", day: "2026-10-14", format: :json)

    assert_response :success
    assert_equal({ "hour" => 9, "sessions" => 1, "waited" => 1, "p95" => 300 }, response.parsed_body["hours"][9])

    get waits_dashboard_path(from: "2026-10-31", to: "2026-10-01", format: :json)

    assert_response :bad_request
  end

  test "a viewer whose workspace still has onboarding to do reaches it all the same" do
    sign_in_as(create(:user, :dashboard_viewer, company: @company, password: AuthHelper::TEST_PASSWORD))

    get dashboard_path

    assert_response :success
  end

  test "anyone who is not a dashboard viewer finds nothing there" do
    sign_in_as(create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD))

    get dashboard_path

    assert_response :not_found

    get waits_dashboard_path(from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :not_found

    get dashboard_company_path(@company, from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :not_found
  end

  test "a stranger is sent to sign in" do
    get dashboard_path

    assert_redirected_to login_path

    get waits_dashboard_path(from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_redirected_to login_path
  end

  test "a superadmin is sent to the admin's own copy" do
    sign_in_as(create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD))

    get dashboard_path

    assert_redirected_to admin_root_path
  end
end
