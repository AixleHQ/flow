# frozen_string_literal: true

require "test_helper"

# Live session and run lists: a model change sends ids only, on signed streams
# that only an authorized page hands out, and the page fetches the rows back
# through an endpoint that serializes them for its own viewer.
class Web::Company::SessionListLiveUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @admin)
  end

  def stream_of(signed) = InertiaCable.signed_stream_verifier.verified(signed)
  def stream_name(*streamables) = InertiaCable::Streams::StreamName.stream_name_from(streamables)

  test "each list page hands out the stream its rows are announced on" do
    sign_in_as(@admin)

    get company_sessions_path
    assert_equal stream_name(@company, :sessions), stream_of(inertia.props[:cableStream])

    get company_project_sessions_path(@project)
    assert_equal stream_name(@project, :sessions_runs), stream_of(inertia.props[:cableStream])

    get user_path(@member)
    assert_equal stream_name(@company, @member, :sessions), stream_of(inertia.props[:sessionsStream])
  end

  test "a member gets company rows back redacted for them, and nothing from another company" do
    @admin.update!(share_active_sessions: false)
    private_session = create(:terminal_session, :agent_session, :running, user: @admin, project: @project,
                                                                          initial_prompt: "salary review")
    elsewhere = create(:terminal_session, :agent_session, user: create(:user, :with_company))
    login = create(:terminal_session, :auth_setup, user: @member, project: nil, company: @company)
    sign_in_as(@member)

    get rows_company_sessions_path(ids: [ private_session.id, elsewhere.id, login.id ])

    assert_response :success
    rows = response.parsed_body["sessions"]
    assert_equal [ private_session.id ], rows.map { |row| row["id"] }
    assert_nil rows.first["initialPrompt"]
    assert_nil rows.first["ideUrl"]
  end

  test "project rows come back only for the project, and only to someone who can open it" do
    session = create(:terminal_session, :agent_session, user: @admin, project: @project)
    run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @admin)
    other_project = create(:project, company: @company, owner: @admin)
    stray = create(:terminal_session, :agent_session, user: @admin, project: other_project)
    sign_in_as(@admin)

    get rows_company_project_sessions_path(@project, session_ids: [ session.id, stray.id ], run_ids: [ run.id ])

    assert_response :success
    entries = response.parsed_body["entries"]
    assert_equal [ [ "session", session.id ], [ "run", run.id ] ], entries.map { |entry| [ entry["kind"], entry["id"] ] }

    outsider = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(outsider)
    get rows_company_project_sessions_path(@project, session_ids: [ session.id ])

    assert_response :not_found
  end
end
