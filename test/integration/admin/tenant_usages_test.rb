# frozen_string_literal: true

require "test_helper"

class Admin::TenantUsagesTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, name: "Acme")
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                                                                password: AuthHelper::TEST_PASSWORD)
  end

  def report_in(body)
    JSON.parse(Nokogiri::HTML(body).at_css("#tenant-usage-report")["data-report"])
  end

  test "the admin home is the tenant report, carrying the daily rows" do
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
  end

  test "someone who is not a superadmin never sees it" do
    sign_in_as(create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD))

    get admin_tenant_usage_path

    assert_redirected_to admin_login_path
  end

  test "recompute starts the rollup workflow over every hour since the date" do
    sign_in_as(@admin)
    TemporalService.expects(:start_workflow)
                   .with(TemporalWorkflowRegistry.workflows["usage_rollup_workflow"],
                         { from_hour: "2026-09-25T00:00:00Z" }, id: "usage_rollup_workflow-recompute")
                   .returns(ok: true, workflow_id: "usage_rollup_workflow-recompute")

    post recompute_admin_tenant_usage_path, params: { since: "2026-09-25" }

    assert_redirected_to admin_tenant_usage_path
    assert_match(/Recomputing usage since 2026-09-25/, flash[:notice])
  end

  test "recompute without a date starts nothing" do
    sign_in_as(@admin)
    TemporalService.expects(:start_workflow).never

    post recompute_admin_tenant_usage_path, params: { since: "" }

    assert_redirected_to admin_tenant_usage_path
    assert_equal "Pick the date to recompute from", flash[:alert]
  end
end
