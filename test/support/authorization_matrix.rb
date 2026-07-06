# frozen_string_literal: true

# Shared harness for request-level authorization tests (docs/testing.md §2,
# "Request (integration): auth, authorization wiring"; Phase 1 policy backfill).
#
# It provides the six canonical personas and role-iterating matrix assertions so
# each controller's authorization test declares only its endpoints (as read or
# write) and any prerequisite records — the role setup and the per-transport
# permit/forbid contract live here, once, instead of being re-derived per file.
#
# Personas (all onboarding_completed so enforce_onboarding, which runs before
# dynamic_authorize!, does not mask the authz outcome):
#   owner         — the project owner (employee)
#   admin         — a company admin who is NOT the owner
#   collaborator  — an employee added as a project collaborator
#   viewer        — a read-only external client, project collaborator
#   stranger      — an employee in the company with no access to the project
#   foreign_admin — an admin of a DIFFERENT company
#
# Response contract (pinned by the pilot):
#   web denial       -> 302 redirect + flash[:alert] "You are not authorized..."
#   api denial       -> 403 {error:"Not authorized"}
#   inaccessible/   \
#   cross-company    -> 404 (scoped `.find` raises RecordNotFound, rescued by
#   record            show_exceptions=:rescuable) — for strangers/foreign users
#   allowed read     -> 200
#   allowed write    -> web: 302 redirect (no alert); api: 2xx
#
# Bullet is disabled in setup: these assert authorization, not query shape (a
# minimal single-record fixture trips Bullet's unused-eager-loading gate, which
# raises in the test env). N+1 is owned by the dedicated controller/perf tests.
module AuthorizationMatrix
  ROLES = %i[owner admin collaborator viewer stranger foreign_admin].freeze
  DENIAL_ALERT = "You are not authorized to perform this action."

  # === persona setup =========================================================

  # Project-scoped controllers. Sets @company, @project, the six persona ivars,
  # and @authz_users. Call from `setup`.
  def setup_project_authz_personas
    @company = create(:company)
    @owner = create_member(:employee)
    @project = create(:project, company: @company, owner: @owner)

    @admin = create_member(:admin) # a company admin, but NOT the project owner
    @collaborator = create_member(:employee)
    @project.add_collaborator(@collaborator)
    @viewer = create_member(:viewer, external: true)
    @project.add_collaborator(@viewer)
    @stranger = create_member(:employee)

    @foreign_company = create(:company)
    @foreign_admin = create(:user, :admin, :onboarding_completed,
                            company: @foreign_company, password: AuthHelper::TEST_PASSWORD)

    build_authz_users
    Bullet.enable = false
  end

  # Company-level controllers (no project). owner/collaborator/stranger are all
  # plain company employees here — the distinction is meaningless for
  # company-level policies, but the uniform role set keeps the matrix helpers
  # usable.
  def setup_company_authz_personas
    @company = create(:company)
    @admin = create_member(:admin)
    @owner = create_member(:employee)
    @collaborator = create_member(:employee)
    @viewer = create_member(:viewer, external: true)
    @stranger = create_member(:employee)

    @foreign_company = create(:company)
    @foreign_admin = create(:user, :admin, :onboarding_completed,
                            company: @foreign_company, password: AuthHelper::TEST_PASSWORD)

    build_authz_users
    Bullet.enable = false
  end

  def teardown_authz
    Bullet.enable = true
  end

  def user_for(role)
    @authz_users.fetch(role)
  end

  # === project-scoped matrices ===============================================
  # The block performs the HTTP request; send a VALID body for writes so the
  # allowed roles get a clean success (denied roles never reach the body —
  # authorization is a before_action). transport: :web (default) or :api.

  # Reads (index/show/etc): accessible to owner/admin/collaborator/viewer;
  # strangers and foreign-company users are scoped out (404).
  def assert_project_read(transport: :web, &block)
    assert_role_matrix(project_read_expectations, transport: transport, &block)
  end

  # Writes (create/update/destroy/custom): allowed for owner/admin/collaborator;
  # denied for the read-only viewer; scoped out (404) for stranger/foreign.
  # `allowed:` overrides the expected status for the allowed roles (e.g.
  # :unprocessable_entity for an endpoint whose body deterministically 422s).
  def assert_project_write(transport: :web, allowed: nil, &block)
    assert_role_matrix(project_write_expectations, transport: transport,
                                                   allowed_status: allowed, &block)
  end

  # === company-level helpers =================================================

  # Every action gated purely on current_user.admin? (e.g. ConfigItems, company
  # Assets). kind: :read or :write. Foreign admin: reads hit their own (empty)
  # data (200); writes on this company's record are scoped out (404).
  def assert_company_admin_only(kind:, transport: :web, allowed: nil, &block)
    ok = kind == :read ? :allowed_read : :allowed_write
    expectations = {
      admin: ok,
      owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied,
      foreign_admin: kind == :read ? :allowed_read : :not_found
    }
    assert_role_matrix(expectations, transport: transport, allowed_status: allowed, &block)
  end

  # === generic escape hatch ==================================================
  # expectations: { role => :allowed_read | :allowed_write | :denied | :not_found }.
  # The block may accept the role symbol (to vary record ids per role).
  def assert_role_matrix(expectations, transport:, allowed_status: nil, &block)
    expectations.each do |role, expected|
      sign_in_as(user_for(role))
      instance_exec(role, &block)
      assert_authz_outcome(expected, transport: transport, role: role, allowed_status: allowed_status)
    end
  end

  # === outcome primitives ====================================================

  def assert_authz_outcome(expected, transport:, role:, allowed_status: nil)
    where = "role=#{role}"
    case expected
    when :allowed_read
      assert_response(allowed_status || :success, where)
    when :allowed_write
      if allowed_status
        assert_response allowed_status, where
      elsif transport == :web
        assert_response :redirect, where
        assert_nil flash[:alert], "#{where}: allowed write must not carry the denial alert"
      else
        assert_response :success, where
      end
    when :denied
      if transport == :web
        assert_response :redirect, where
        assert_equal DENIAL_ALERT, flash[:alert], "#{where}: expected the authorization denial alert"
      else
        assert_response :forbidden, where
      end
    when :not_found
      assert_response :not_found, where
    else
      raise ArgumentError, "unknown authz expectation: #{expected.inspect}"
    end
  end

  private

  def create_member(role, external: false)
    attrs = { company: @company, password: AuthHelper::TEST_PASSWORD }
    # Viewers are external clients: their email domain must NOT match the company
    # (the email_domain_matches_company validation skips read_only? users).
    attrs[:email] = "client-#{SecureRandom.hex(3)}@external.com" if external
    create(:user, role, :onboarding_completed, **attrs)
  end

  def build_authz_users
    @authz_users = {
      owner: @owner, admin: @admin, collaborator: @collaborator,
      viewer: @viewer, stranger: @stranger, foreign_admin: @foreign_admin
    }
  end

  def project_read_expectations
    {
      owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
      viewer: :allowed_read, stranger: :not_found, foreign_admin: :not_found
    }
  end

  def project_write_expectations
    {
      owner: :allowed_write, admin: :allowed_write, collaborator: :allowed_write,
      viewer: :denied, stranger: :not_found, foreign_admin: :not_found
    }
  end
end
