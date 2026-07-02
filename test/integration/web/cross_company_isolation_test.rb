# frozen_string_literal: true

require "test_helper"

# Cross-company isolation suite: a dual-membership user (admin in A, viewer in
# B) must only ever see the CURRENT company's data, on every screen, and the
# slice must flip completely after POST /company/switch.
class Web::CrossCompanyIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @company_a = create(:company, name: "Alpha")
    @company_b = create(:company, name: "Beta")

    @user = create(:user, :admin, :onboarding_completed, company: @company_a, password: AuthHelper::TEST_PASSWORD)
    @membership_a = @user.company_memberships.find_by!(company: @company_a).tap { |m| m.update!(accepted_at: 2.days.ago) }
    @membership_b = create(:company_membership, :viewer, user: @user, company: @company_b, accepted_at: 1.day.ago)

    @colleague_b = create(:user, :employee, :onboarding_completed, company: @company_b)

    @project_a = create(:project, name: "Alpha Project", company: @company_a, owner: @user)
    @project_b = create(:project, name: "Beta Project", company: @company_b, owner: @colleague_b)
    # Viewer visibility follows the normal collaborator mechanism (#213 design).
    create(:project_collaborator, project: @project_b, user: @user)

    seed_session(project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(project: @project_b, cost_cents: 250, tokens: 500)
    create(:workflow_run, project: @project_a, user: @user, workflow: create(:workflow, scope: @project_a))
    create(:workflow_run, project: @project_b, user: @user, workflow: create(:workflow, scope: @project_b))

    sign_in_as(@user)
  end

  def seed_session(project:, cost_cents:, tokens:, user: @user)
    session = build(:terminal_session, user:, project:, session_type: "agent_session", agent_type: "claude_code")
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents:, input_tokens: tokens, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens:
    )
    session
  end

  def switch_to(company)
    post company_switch_path, params: { company_id: company.id }
    assert_redirected_to company_projects_path
  end

  def usage_props
    get usage_profile_path
    inertia_load_deferred_props("usage")
    inertia.props
  end

  # === /profile/usage ===

  test "usage shows only the current company's sessions, costs and workflows, and flips after a switch" do
    props = usage_props
    assert_equal 1, props[:summary][:totalSessions]
    assert_equal 100, props[:summary][:totalCostCents]
    assert_equal 1000, props[:summary][:totalTokens]
    assert_equal 1, props[:summary][:workflowsRun]
    assert_equal [ "Alpha Project" ], props[:summary][:projectBreakdowns].map { |p| p[:projectName] }
    assert_equal [ "Alpha Project" ], props[:sessions].map { |s| s[:projectName] }.uniq
    assert_equal 1, props[:activityHeatmap][:days].sum { |d| d[:count] }

    switch_to(@company_b)

    props = usage_props
    assert_equal 1, props[:summary][:totalSessions]
    assert_equal 250, props[:summary][:totalCostCents]
    assert_equal 500, props[:summary][:totalTokens]
    assert_equal 1, props[:summary][:workflowsRun]
    assert_equal [ "Beta Project" ], props[:summary][:projectBreakdowns].map { |p| p[:projectName] }
    assert_equal [ "Beta Project" ], props[:sessions].map { |s| s[:projectName] }.uniq
  end

  test "usage colleague param for a user of the other company is a 404" do
    # Current company is A; @colleague_b is only a member of B.
    get usage_profile_path(user_id: @colleague_b.id)
    assert_response :not_found

    # In B the same colleague is visible.
    switch_to(@company_b)
    get usage_profile_path(user_id: @colleague_b.id)
    assert_response :success
  end

  # === members ===

  test "members index never lists the other company's users" do
    get company_members_path
    emails = inertia.props[:users].map { |u| u[:email] }
    assert_includes emails, @user.email
    assert_not_includes emails, @colleague_b.email

    switch_to(@company_b)

    get company_members_path
    emails = inertia.props[:users].map { |u| u[:email] }
    assert_includes emails, @colleague_b.email
    assert_includes emails, @user.email
    assert_not emails.include?(nil)
  end

  # === /company/sessions ===

  test "company sessions index shows only the current company's project sessions and flips after a switch" do
    # The sessions screen is admin-gated; promote the user in B for this test.
    @membership_b.update!(role: "admin")
    # A project-less session follows company_sessions_scope's documented rule:
    # it belongs to EVERY company the user is an active member of.
    projectless = build(:terminal_session, user: @user, project: nil,
                                           session_type: "agent_session", agent_type: "claude_code")
    projectless.save!(validate: false)

    get company_sessions_path
    names = inertia.props[:sessions].map { |s| s[:projectName] }
    assert_includes names, "Alpha Project"
    assert_not_includes names, "Beta Project"
    assert_includes names, nil, "project-less session missing in A"

    switch_to(@company_b)

    get company_sessions_path
    names = inertia.props[:sessions].map { |s| s[:projectName] }
    assert_includes names, "Beta Project"
    assert_not_includes names, "Alpha Project"
    assert_includes names, nil, "project-less session missing in B"
  end

  # === projects ===

  test "projects index is scoped to the current company" do
    get company_projects_path
    assert_equal [ "Alpha Project" ], inertia.props[:projects].map { |p| p[:name] }

    switch_to(@company_b)

    get company_projects_path
    names = inertia.props[:projects].map { |p| p[:name] }
    assert_not_includes names, "Alpha Project"
  end

  # === revocation removes project access, even for owners ===

  test "revoking the membership in B strips a B-project owner of access" do
    owner_b = create(:user, :employee, :onboarding_completed, company: @company_b)
    project = create(:project, name: "Owned in Beta", company: @company_b, owner: owner_b)

    assert Project.for_user(owner_b).exists?(id: project.id)
    assert project.accessible_by?(owner_b)

    owner_b.company_memberships.find_by!(company: @company_b).revoke!

    assert_not Project.for_user(owner_b).exists?(id: project.id), "owner keeps for_user access after revocation"
    assert_not project.reload.accessible_by?(owner_b), "owner keeps accessible_by? after revocation"
  end

  test "revoking the membership in B strips a B-project collaborator of access" do
    assert Project.for_user(@user).exists?(id: @project_b.id)
    assert @project_b.accessible_by?(@user)

    @membership_b.revoke!

    assert_not Project.for_user(@user).exists?(id: @project_b.id)
    assert_not @project_b.reload.accessible_by?(@user)
    # Access in A is untouched.
    assert Project.for_user(@user).exists?(id: @project_a.id)
  end

  # === write permissions per company (policy level) ===

  test "viewer-in-B cannot write in B's projects while admin-in-A can in A" do
    policy_a = Web::Company::Projects::Board::TasksPolicy.new(
      ProjectContext.new(@user, ActionController::Parameters.new, project: @project_a), nil
    )
    assert policy_a.create?
    assert policy_a.update?

    policy_b = Web::Company::Projects::Board::TasksPolicy.new(
      ProjectContext.new(@user, ActionController::Parameters.new, project: @project_b), nil
    )
    assert policy_b.index?, "viewer keeps read access"
    assert_not policy_b.create?
    assert_not policy_b.update?
    assert_not policy_b.destroy?
  end
end
