# frozen_string_literal: true

require "test_helper"

# Manual catalog triggers. Both mirrors fill on a schedule, so this page exists for the
# window where a fresh deployment would otherwise show an empty catalog.
class Admin::CatalogSyncsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    # `authenticate_admin!` gates on the platform-level super_admin flag, not on a
    # company admin membership.
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  test "index shows what each catalog currently holds" do
    create(:catalog_skill, registry_id: "anthropics/skills/pdf", source: "anthropics/skills", slug: "pdf",
           description: "Fill PDF forms")
    create(:connector, name: "io.github.example/server")

    get admin_catalog_syncs_path

    assert_response :success
    assert_match(/Catalog syncs/, response.body)
    assert_match(/1 entries/, response.body)
    assert_match(/1 described/, response.body)
  end

  # The work is a few hundred paced outbound requests: it belongs in the workflow the
  # schedule uses, not in this request.
  test "triggering a sync starts the same workflow the schedule starts" do
    started = nil
    TemporalService.stubs(:start_workflow).with do |workflow, _input, options|
      started = [ workflow.name, options[:id] ]
      true
    end.returns({ ok: true, workflow_id: "skills_catalog_sync_workflow-manual" })

    post admin_catalog_syncs_path, params: { catalog: "skills" }

    assert_redirected_to admin_catalog_syncs_path
    assert_equal [ "skills_catalog_sync_workflow", "skills_catalog_sync_workflow-manual" ], started
    assert_match(/sync started/, flash[:notice])
  end

  test "triggering the connector catalog starts its own workflow" do
    started = nil
    TemporalService.stubs(:start_workflow).with do |workflow, _input, _options|
      started = workflow.name
      true
    end.returns({ ok: true, workflow_id: "x" })

    post admin_catalog_syncs_path, params: { catalog: "connectors" }

    assert_equal "mcp_connector_catalog_sync_workflow", started
  end

  # A stable workflow id means Temporal refuses a concurrent duplicate; the operator is
  # told rather than left thinking nothing happened.
  test "a refused start is reported" do
    TemporalService.stubs(:start_workflow).returns({ ok: false, error: "Workflow already started" })

    post admin_catalog_syncs_path, params: { catalog: "skills" }

    assert_match(/Could not start/, flash[:alert])
    assert_match(/already started/, flash[:alert])
  end

  test "an unknown catalog is refused" do
    TemporalService.expects(:start_workflow).never

    post admin_catalog_syncs_path, params: { catalog: "nonsense" }

    assert_match(/Unknown catalog/, flash[:alert])
  end

  # The navigation override enumerates admin routes, and a route without a dashboard
  # used to raise there — which would have broken every Administrate page, not just
  # this one.
  test "existing Administrate pages still render with the extra nav link" do
    get admin_skills_path
    assert_response :success

    get admin_users_path
    assert_response :success
    assert_match(/Catalog syncs/, response.body)
  end

  test "a non-admin cannot reach the page" do
    member = create(:user, :admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    # A fresh session: signing in again would otherwise ride the super_admin cookie
    # already set in setup, and the test would prove nothing.
    reset!
    sign_in_as(member)

    get admin_catalog_syncs_path

    assert_response :redirect
    assert_not_equal admin_catalog_syncs_path, response.location
  end
end
