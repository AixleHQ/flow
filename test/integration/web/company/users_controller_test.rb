# frozen_string_literal: true

require "test_helper"

# The organization-visible member profile at /user/:id.
class Web::Company::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @colleague = create(:user, :admin, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @colleague)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  def seed_session(user:, project: @project, session_type: "agent_session", state: "finished", **attrs)
    session = build(:terminal_session, user:, project:, session_type:, state:, **attrs)
    session.save!(validate: false)
    session
  end

  test "renders the member profile for a colleague in the same company" do
    get user_path(@colleague)

    assert_response :success
    assert_inertia_page "Company/Users/Show"
    assert_inertia_props viewerIsSelf: false
    assert_inertia_props do |props|
      props[:member][:id] == @colleague.id && props[:member][:email] == @colleague.email
    end
  end

  test "the viewer can open their own profile at the same URL" do
    get user_path(@user)

    assert_inertia_props viewerIsSelf: true
  end

  test "lists the subject's sessions and workflow steps, not anybody else's" do
    mine = seed_session(user: @colleague)
    step = seed_session(user: @colleague, session_type: "workflow_step")
    theirs = seed_session(user: @user)

    get user_path(@colleague)

    assert_inertia_props do |props|
      ids = props[:sessions].map { |s| s[:id] }
      ids.sort == [ mine.id, step.id ].sort && ids.exclude?(theirs.id)
    end
    assert_inertia_props total: 2
  end

  test "auth_setup sessions stay off the list — they are plumbing, and owner-only" do
    seed_session(user: @colleague, project: nil, session_type: "auth_setup")

    get user_path(@colleague)

    assert_inertia_props sessions: [], total: 0
  end

  # A dual-membership user's work in another company must not surface here.
  test "sessions from another company are excluded" do
    other_company = create(:company)
    create(:company_membership, user: @colleague, company: other_company)
    other_project = create(:project, company: other_company, owner: @colleague)
    foreign = seed_session(user: @colleague, project: other_project)
    mine = seed_session(user: @colleague)

    get user_path(@colleague)

    assert_inertia_props do |props|
      ids = props[:sessions].map { |s| s[:id] }
      ids == [ mine.id ] && ids.exclude?(foreign.id)
    end
  end

  # The row survives; the prompt does not. Opening it is refused separately, by
  # Web::Company::SessionsController#show.
  test "a session the owner keeps private is listed but not viewable" do
    @colleague.update!(share_completed_sessions: false, share_active_sessions: false)
    private_session = seed_session(user: @colleague, initial_prompt: "secret migration plan")

    get user_path(@colleague)

    assert_inertia_props do |props|
      row = props[:sessions].find { |s| s[:id] == private_session.id }
      row.present? && row[:viewable] == false && row[:initialPrompt].nil?
    end
  end

  test "a shared session keeps its prompt for a colleague" do
    @colleague.update!(share_completed_sessions: true)
    shared = seed_session(user: @colleague, initial_prompt: "rename the billing job")

    get user_path(@colleague)

    assert_inertia_props do |props|
      row = props[:sessions].find { |s| s[:id] == shared.id }
      row[:viewable] == true && row[:initialPrompt] == "rename the billing job"
    end
  end

  # The page renders rows the viewer may have no route to. Which ones those are
  # is a server answer, so the row does not become a link that only redirects.
  test "reports the viewer's own reach: admin flag plus the projects they can open a session in" do
    mine = create(:project, company: @company, owner: @user)
    create(:project, company: @company, owner: @colleague)

    get user_path(@colleague)

    assert_inertia_props viewerIsAdmin: false
    assert_inertia_props do |props|
      props[:accessibleProjectIds] == [ mine.id ]
    end
  end

  test "a company admin can reach every project in the company" do
    delete logout_path
    admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(admin)

    get user_path(@colleague)

    assert_inertia_props viewerIsAdmin: true
    assert_inertia_props do |props|
      props[:accessibleProjectIds].include?(@project.id)
    end
  end

  # The card reads the vendor over HTTP; blocking the page on it would mean a
  # throttled provider blanks the session list too.
  test "defers the usage limits prop rather than blocking the render on the vendor" do
    get user_path(@colleague)

    assert_inertia_deferred_props :usage_limits, group: "limits"
    assert_inertia_props do |props|
      !props.key?(:usageLimits)
    end
  end

  test "the deferred usage limits prop resolves to an empty list when no credential bills against a plan" do
    create(:agent_credential, user: @colleague, company: @company, agent_type: "claude_code",
                              config_data: { "awsBedrock" => { "region" => "us-east-1" } })

    get user_path(@colleague)
    inertia_load_deferred_props("limits")

    assert_inertia_props usageLimits: []
  end

  # Aixle spend, alongside the vendor allowance. Same services and deferral
  # group as Profile -> Usage, so a slow query never delays the first paint.
  test "defers the spend analytics props and defaults the window to 30 days" do
    get user_path(@colleague)

    assert_inertia_props period: "30d"
    assert_inertia_deferred_props :summary, :agent_activity, :cost_token, :activity_heatmap, group: "usage"
  end

  test "the deferred analytics resolve to the subject's spend in this company" do
    seed_session(user: @colleague).tap do |session|
      UsageStatistic.create!(terminal_session: session, cost_cents: 300, input_tokens: 3000, output_tokens: 0,
                             cache_write_tokens: 0, cache_read_tokens: 0, tokens: 3000)
    end
    seed_session(user: @user).tap do |session|
      UsageStatistic.create!(terminal_session: session, cost_cents: 999, input_tokens: 9999, output_tokens: 0,
                             cache_write_tokens: 0, cache_read_tokens: 0, tokens: 9999)
    end

    get user_path(@colleague)
    inertia_load_deferred_props("usage")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:totalCostCents] == 300 &&
        props[:summary][:totalTokens] == 3000 &&
        props[:activityHeatmap][:days].length == 1
    end
  end

  test "an unknown period falls back to the default instead of reaching the services" do
    get user_path(@colleague, period: "all-time")

    assert_inertia_props period: "30d"
  end

  test "a supported period is passed through" do
    get user_path(@colleague, period: "7d")

    assert_inertia_props period: "7d"
  end

  test "a member of another company is a 404, not a 403" do
    other_company = create(:company)
    stranger = create(:user, :employee, :onboarding_completed, company: other_company)

    get user_path(stranger)

    assert_response :not_found
  end

  test "an unknown user id is a 404" do
    get user_path(id: User.maximum(:id).to_i + 1000)

    assert_response :not_found
  end

  test "a revoked member has no page" do
    membership = CompanyMembership.find_by!(user: @colleague, company: @company)
    membership.aasm(:state).fire!(:revoke)

    get user_path(@colleague)

    assert_response :not_found
  end

  # Members lists invited and suspended people, and its rows link here — a 404
  # on those would make the list lie about where its own links go.
  test "invited and suspended members still have a page" do
    invited = create(:user, :employee, company: @company)
    CompanyMembership.find_by!(user: invited, company: @company).update!(state: "invited")

    suspended = create(:user, :employee, :onboarding_completed, company: @company)
    CompanyMembership.find_by!(user: suspended, company: @company).aasm(:state).fire!(:suspend)

    get user_path(invited)
    assert_response :success

    get user_path(suspended)
    assert_response :success
  end

  test "a viewer gets the same read as everybody else" do
    delete logout_path
    viewer = create(:user, :viewer, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    get user_path(@colleague)

    assert_response :success
    assert_inertia_page "Company/Users/Show"
  end

  test "a logged-out request cannot load the page" do
    delete logout_path

    get user_path(@colleague)

    assert_redirected_to login_path
  end
end
