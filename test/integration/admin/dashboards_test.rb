# frozen_string_literal: true

require "test_helper"

class Admin::DashboardsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, name: "Acme")
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                                                                password: AuthHelper::TEST_PASSWORD)
  end

  def report_in(body)
    JSON.parse(Nokogiri::HTML(body).at_css("#admin-dashboard")["data-report"])
  end

  test "the admin home is the dashboard, carrying the daily rows and the platform's size" do
    CompanyUsageHour.create!(company: @company, period_start: Time.utc(2026, 10, 14, 9), billing_class: "managed",
                             occupied_seconds: 1_800, computed_at: Time.utc(2026, 10, 14, 10, 10))
    sign_in_as(@admin)

    get admin_root_path

    assert_response :success
    report = report_in(response.body)
    assert_equal [ { "id" => @company.id, "name" => "Acme" } ], report["tenants"]
    day = report["days"].sole
    assert_equal 1_800, day["occupiedSeconds"]
    assert_equal "managed", day["billingClass"]
    assert_equal "2026-10-14T10:00:00Z", report["measuredThrough"]
    assert_equal Company.active.count, report["snapshot"]["companies"]
  end

  test "someone who is not a superadmin never sees it" do
    sign_in_as(create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD))

    get admin_dashboard_path

    assert_redirected_to admin_login_path

    get admin_dashboard_company_path(@company, from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_redirected_to admin_login_path

    get waits_admin_dashboard_path(from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_redirected_to admin_login_path
  end

  test "a company opened from the dashboard carries its queue over the chosen days" do
    owner = create(:user, company: @company)
    project = create(:project, company: @company, owner: owner)
    pool = SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 4, policy_revision: 1)
    SessionAdmission.create!(terminal_session: create(:terminal_session, :agent_session, project: project, user: owner),
                             session_admission_pool: pool, created_at: Time.utc(2026, 10, 14, 9),
                             admitted_at: Time.utc(2026, 10, 14, 9, 5))
    sign_in_as(@admin)

    get admin_dashboard_company_path(@company, from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :success
    body = response.parsed_body
    assert_equal @company.id, body["companyId"]
    assert_equal [ 1, 1, 300 ], body["waits"].values_at("sessions", "waited", "p95")
    assert_equal [ project.name ], body["projects"].pluck("name")
    assert_equal [ { "day" => "2026-10-14", "sessions" => 1, "waited" => 1, "p95" => 300 } ], body["days"]
  end

  test "the table reads every company's p95 wait for the chosen days" do
    owner = create(:user, company: @company)
    project = create(:project, company: @company, owner: owner)
    pool = SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 4, policy_revision: 1)
    SessionAdmission.create!(terminal_session: create(:terminal_session, :agent_session, project: project, user: owner),
                             session_admission_pool: pool, created_at: Time.utc(2026, 10, 14, 9),
                             admitted_at: Time.utc(2026, 10, 14, 9, 5))
    sign_in_as(@admin)

    get waits_admin_dashboard_path(from: "2026-10-01", to: "2026-10-31", format: :json)

    assert_response :success
    assert_equal [ { "companyId" => @company.id, "p95" => 300 } ], response.parsed_body

    get waits_admin_dashboard_path(from: "2026-10-31", to: "2026-10-01", format: :json)
    assert_response :bad_request
  end

  test "a company opened with days that do not parse is a bad request" do
    sign_in_as(@admin)

    get admin_dashboard_company_path(@company, from: "October", to: "2026-10-31", format: :json)
    assert_response :bad_request

    get admin_dashboard_company_path(@company, from: "2026-10-31", to: "2026-10-01", format: :json)
    assert_response :bad_request
  end
end
