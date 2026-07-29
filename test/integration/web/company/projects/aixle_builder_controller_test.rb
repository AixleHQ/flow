# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AixleBuilderControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  # ── show ──────────────────────────────────────────

  test "show renders landing page" do
    get company_project_aixle_builder_path(@project)
    assert_inertia_page "Projects/AixleBuilder/LandingPage"
  end

  test "show includes sessions in response" do
    create(:terminal_session, :aixle_builder, user: @user, project: @project)

    get company_project_aixle_builder_path(@project)
    assert_inertia_page "Projects/AixleBuilder/LandingPage"
  end

  test "show does not issue N+1 queries when multiple sessions exist" do
    tools = create_list(:tool, 2, scope: @project)
    skills = create_list(:skill, 2, scope: @project)
    3.times do
      session = create(:terminal_session, :aixle_builder, user: @user, project: @project)
      session.tools << tools
      session.skills << skills
    end

    # Count only real content queries. SCHEMA reflection and query-cache hits are
    # issued non-deterministically depending on process warmth (a cold isolated run
    # vs a warm parallel-suite run differ by ~8 queries) and shift with unrelated
    # gem internals, which made a raw count flaky. Filtering them leaves the actual
    # association loading — what an N+1 guard cares about — which is stable at 15.
    query_count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if payload[:sql].to_s.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      query_count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get company_project_aixle_builder_path(@project)
    end

    assert_response :success
    # O(1) regardless of session count: 1 primary + a bounded set of association
    # batch loads (verified flat at 19 for both 3 and 8 sessions).
    #
    # 15 -> 19 with CompanyMembership. All four additions are constant, and the
    # flatness above is what this guard actually protects:
    #   +1  the active-membership list, which used to come free from
    #       users.company_id on the already-loaded user row. Memoized per User
    #       instance (User#active_memberships), so it stays one query however
    #       many policies and permission props the request builds.
    #   +1  Project#accessible_by?, which used to be an integer comparison and
    #       is now a membership lookup. Deliberately NOT memoized — see the
    #       comment there; a stale answer would grant revoked access.
    #   +1  the companies preload behind the current-user `memberships` prop,
    #       which feeds the company switcher. There was no membership list to
    #       serialize before, so this has no pre-membership counterpart.
    #   +1  the users.last_company_id write that makes the switcher choice
    #       survive a new session. Once per session, on the first request that
    #       resolves a membership — which a test always starts fresh, so it is
    #       always counted here.
    assert_operator query_count, :<=, 19, "Expected bounded content query count, got #{query_count}"
  end

  # ── start ─────────────────────────────────────────

  test "start creates session and redirects to session page" do
    SessionService.stubs(:create_and_start).returns(
      create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)
    )

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }
    assert_response :redirect
    assert_match %r{/aixle_builder/\d+/session}, response.location
  end

  test "start attaches every builder meta tool to the session" do
    captured = nil
    SessionService.stubs(:create_and_start).with do |**kwargs|
      captured = kwargs
      true
    end.returns(create(:terminal_session, :aixle_builder, :started, user: @user, project: @project))

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }

    assert_response :redirect
    # Regression: Builder sessions were once created with zero tools (the
    # controller queried a stale kind after migration 20260627000002). Meta
    # tools now come from the code registry, materialized as shadow rows on
    # demand — no pre-seeded rows required.
    attached = Tool.where(id: captured[:params][:tool_ids])
    assert_equal Tools::Registry.tagged(:builder).map(&:name).sort, attached.pluck(:name).sort
    assert_equal 28, attached.count
  end

  test "start redirects back with flash alert when session save fails" do
    unsaved = TerminalSession.new
    unsaved.errors.add(:base, "Test validation failure")
    SessionService.stubs(:create_and_start).returns(unsaved)

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }
    assert_redirected_to company_project_aixle_builder_path(@project)
    assert_equal "Test validation failure", flash[:alert]
  end

  # ── session ───────────────────────────────────────

  test "session renders session page for own session" do
    ts = create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)

    get company_project_aixle_builder_session_path(@project, ts)
    assert_inertia_page "Projects/AixleBuilder/SessionPage"
  end

  test "session returns 404 for another users session" do
    other_user = create(:user, company: @company)
    ts = create(:terminal_session, :aixle_builder, user: other_user, project: @project)

    get company_project_aixle_builder_session_path(@project, ts)
    assert_response :not_found
  end

  # ── finish ────────────────────────────────────────

  test "finish delegates to SessionService and redirects" do
    ts = create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)
    SessionService.stubs(:finish)

    post company_project_aixle_builder_finish_path(@project, ts)
    assert_redirected_to company_project_aixle_builder_session_path(@project, ts)
  end
end
