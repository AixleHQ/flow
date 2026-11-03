# frozen_string_literal: true

require "test_helper"

class AnalyticsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @company = create(:company, email_domain: "acme.test", billing_state: "trialing")
    @user = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                          analytics_consent: "granted")
  end

  test "sends nothing without a key, or from the test settings' self-hosted default" do
    Analytics.capture("project_created", user: @user, company: @company)
    enable_analytics!(api_key: nil)
    Analytics.capture("project_created", user: @user, company: @company)

    assert_empty analytics_events
  end

  test "sends nothing from a self-hosted or Marketplace deployment even with a key" do
    [ Deployment::SELF_HOSTED, Deployment::AWS_MARKETPLACE ].each do |mode|
      enable_analytics!(mode: mode)
      Analytics.capture("project_created", user: @user, company: @company)
    end

    assert_empty analytics_events
  end

  test "sends nothing for a person who refused or was never asked" do
    enable_analytics!
    [ "denied", nil ].each do |consent|
      @user.update!(analytics_consent: consent)
      Analytics.capture("project_created", user: @user, company: @company)
    end

    assert_empty analytics_events
  end

  test "sends nothing while a super admin impersonates someone" do
    enable_analytics!
    admin = create(:user, :super_admin)
    Current.user_session = create(:user_session, user: @user, impersonator: admin)

    Analytics.capture("project_created", user: @user, company: @company)

    assert_empty analytics_events
  end

  test "a consented event carries the person's id and every common property, and no name or email" do
    enable_analytics!
    project = create(:project, company: @company, owner: @user)

    Analytics.capture("project_created", user: @user, company: @company, project: project, props: { is_first: true },
                                         via: "mcp")

    event = analytics_event("project_created")
    assert_equal @user.id.to_s, event["distinct_id"]
    assert_equal({ "company_id" => @company.id, "billing_status" => "trialing", "managed" => false,
                   "internal_company" => false, "user_role" => "admin", "onboarding_state" => "completed",
                   "project_id" => project.id, "via" => "mcp", "is_first" => true },
                 event["properties"].slice("company_id", "billing_status", "managed", "internal_company", "user_role",
                                           "onboarding_state", "project_id", "via", "is_first"))
    assert_equal({ "signup_date" => @user.created_at.to_date.iso8601 }, event["properties"]["$set_once"])
    assert_not_includes event.to_json, @user.email
    assert_not_includes event.to_json, @user.name
  end

  test "our own test tenant is marked internal" do
    enable_analytics!
    @company.update!(email_domain: "acmeorbit.com")

    Analytics.capture("project_created", user: @user, company: @company)

    assert analytics_event("project_created")["properties"]["internal_company"]
  end

  test "track charges the event to whoever is acting, and to nobody when no one is" do
    enable_analytics!
    Analytics.track("board_task_created", company: @company)
    assert_empty analytics_events

    Current.analytics_actor = @user
    Current.analytics_via = "ui"
    Analytics.track("board_task_created", company: @company)

    assert_equal [ "board_task_created" ], analytics_event_names
    assert_equal "ui", analytics_event("board_task_created")["properties"]["via"]
  end

  test "an anonymous visit is reported under the browser's id, and joined to the account later" do
    enable_analytics!

    Analytics.capture_anonymous("signup_email_sent", distinct_id: "anon-123")
    Analytics.alias_anonymous(user: @user, anonymous_id: "anon-123")

    sent, aliased = analytics_events
    assert_equal "anon-123", sent["distinct_id"]
    assert_equal "$create_alias", aliased["event"]
    assert_equal({ "distinct_id" => @user.id.to_s, "alias" => "anon-123" }, aliased["properties"])
  end

  test "a failure to enqueue never reaches the caller" do
    enable_analytics!
    Analytics::CaptureJob.stubs(:perform_later).raises(StandardError, "queue down")

    assert_nothing_raised { Analytics.capture("project_created", user: @user, company: @company) }
  end
end
