# frozen_string_literal: true

require "test_helper"

# A fresh installation turns the queue on in the migration; an installation with
# history has to do it deliberately, and its operator may have an admin login
# and nothing else.
class Admin::SessionAdmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
    @owner = create(:user, company: @company)
    SessionAdmissionPolicy.current.update!(enabled: false, paused: true, installation_limit: nil)
  end

  teardown { restore_scope_defaults }

  test "the page reports what the environment currently resolves to" do
    with_scope_defaults(project: 3, user: 5)

    get admin_session_admission_path

    assert_response :success
    assert_match(/Not enabled/, response.body)
    assert_match(/3 each/, response.body)
    assert_match(/5 each/, response.body)
  end

  test "enabling reads the cap from the environment rather than the form" do
    ENV["SESSION_CONCURRENCY_LIMIT"] = "7"
    SessionRuntimeInventory.stubs(:fetch).returns([])

    patch admin_session_admission_path, params: { commit_action: "activate" }

    assert SessionAdmissionPolicy.current.enabled?
    assert_equal 7, SessionAdmissionPolicy.current.installation_limit
  ensure
    ENV.delete("SESSION_CONCURRENCY_LIMIT")
  end

  test "enabling is refused while the runtime still holds legacy session resources" do
    SessionRuntimeInventory.stubs(:fetch).returns([ "Pod aixle-dev-project-1/terminal-abc" ])

    patch admin_session_admission_path, params: { commit_action: "activate" }

    assert_not SessionAdmissionPolicy.current.enabled?,
      "a leftover Pod answers to no reservation, so the queue would hand out capacity already spent"
    assert_match(/terminal-abc/, flash[:alert])
  end

  test "a runtime we cannot read is refused rather than treated as empty" do
    SessionRuntimeInventory.stubs(:fetch).raises(SessionRuntimeInventory::Unavailable, "Temporal is disabled")

    patch admin_session_admission_path, params: { commit_action: "activate" }

    assert_not SessionAdmissionPolicy.current.enabled?
    assert_match(/Temporal is disabled/, flash[:alert])
  end

  test "enabling is refused while a session is still running, and says so" do
    SessionRuntimeInventory.stubs(:fetch).returns([])
    create(:terminal_session, user: @owner, state: "running", started_at: Time.current)

    patch admin_session_admission_path, params: { commit_action: "activate" }

    assert_not SessionAdmissionPolicy.current.enabled?, "live sessions must not be put behind a queue they never entered"
    assert_match(/drain/i, flash[:alert])
  end

  test "pausing keeps occupied slots and resuming admits what waited" do
    SessionRuntimeInventory.stubs(:fetch).returns([])
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    first = SessionAdmissionService.enqueue!(create(:terminal_session, user: @owner))
    second = SessionAdmissionService.enqueue!(create(:terminal_session, user: @owner))
    SessionAdmissionService.drain!

    patch admin_session_admission_path, params: { commit_action: "pause" }
    assert SessionAdmissionPolicy.current.paused?
    assert first.reload.admitted_at, "pausing must not evict a reservation"

    SessionAdmissionService.cancel!(first.terminal_session)
    patch admin_session_admission_path, params: { commit_action: "resume" }

    assert_not SessionAdmissionPolicy.current.paused?
    assert second.reload.admitted_at
  end
end
