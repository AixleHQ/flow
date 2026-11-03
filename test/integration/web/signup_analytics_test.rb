# frozen_string_literal: true

require "test_helper"

# The company signup funnel (signup → confirmation → onboarding) as PostHog
# sees it: one person from the first page to the finished onboarding, even when
# the emailed link is opened in another browser, and nobody at all without consent.
class Web::SignupAnalyticsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    enable_analytics!
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: true))
  end

  def sign_up(**analytics)
    perform_enqueued_jobs(only: MailDeliveryJob) do
      post workspace_path, params: { workspace: { name: "Acme Robotics", email: "dana@acme-robotics.example",
                                                  **analytics } }
    end
  end

  # The link a stranger was mailed, opened in a browser that never saw the form.
  def open_emailed_link
    mail = ActionMailer::Base.deliveries.last
    link = (mail.text_part || mail.html_part || mail).body.decoded[%r{https?://[^\s"<>]*/workspace/confirm\?token=[^\s"<>]+}]
    reset!
    get URI(link).request_uri
  end

  def owner = User.find_by(email: "dana@acme-robotics.example")

  test "a consenting stranger is one person from the signup form to the workspace, across browsers" do
    sign_up(analytics_consent: "granted", analytics_id: "anon-browser-1")
    assert_equal({ "event" => "signup_email_sent", "distinct_id" => "anon-browser-1" },
                 analytics_event("signup_email_sent").slice("event", "distinct_id"))

    travel 7.minutes do
      open_emailed_link
    end

    assert_equal "granted", owner.analytics_consent
    company = Company.find_by(email_domain: "acme-robotics.example")
    assert_equal owner, company.created_by

    aliased = analytics_event("$create_alias")
    assert_equal({ "distinct_id" => owner.id.to_s, "alias" => "anon-browser-1" }, aliased["properties"])
    created = analytics_event("workspace_created")
    assert_equal owner.id.to_s, created["distinct_id"]
    assert_equal "magic_link", created["properties"]["auth_method"]
    assert_equal 7, created["properties"]["minutes_since_email"]
    assert_equal company.id, created["properties"]["company_id"]
  end

  test "a stranger who declined is not reported, and the refusal is kept on the account" do
    sign_up(analytics_consent: "denied", analytics_id: "anon-browser-1")
    open_emailed_link

    assert_equal "denied", owner.analytics_consent
    assert_empty analytics_events
  end

  test "a stranger who never answered is not reported, and is asked inside the app" do
    sign_up
    open_emailed_link

    assert_nil owner.analytics_consent
    assert_empty analytics_events
  end

  test "the founder's onboarding is reported step by step as a signup" do
    company = create(:company)
    founder = create(:user, company: company, membership_role: "admin", password: AuthHelper::TEST_PASSWORD,
                            analytics_consent: "granted")
    sign_in_as(founder)

    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en", onboarding_state_event: "go_next" }
    }
    patch onboarding_path, params: { onboarding: { onboarding_state_event: "skip_agent_setup" } }

    assert_equal %w[onboarding_step_completed onboarding_agent_skipped onboarding_step_completed onboarding_completed],
                 analytics_event_names
    assert_equal({ "step" => "profile", "entry" => "signup", "position" => "dev", "language" => "en" },
                 analytics_events.first["properties"].slice("step", "entry", "position", "language"))
    assert_equal "agents", analytics_events.third["properties"]["step"]
  end

  test "an invited member's onboarding is reported as an invite, so the signup funnel leaves it out" do
    company = create(:company)
    member = create(:user, company: company, password: AuthHelper::TEST_PASSWORD, analytics_consent: "granted")
    member.company_memberships.first.update!(invited_at: 1.day.ago)
    sign_in_as(member)

    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en", onboarding_state_event: "go_next" }
    }

    assert_equal "invite", analytics_event("onboarding_step_completed")["properties"]["entry"]
  end
end
