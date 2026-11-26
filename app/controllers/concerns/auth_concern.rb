# frozen_string_literal: true

module AuthConcern
  extend ActiveSupport::Concern

  IMPERSONATION_KEY = "true_user_id"
  # Carried across the session reset at sign-in: what the flow signing the person
  # in has just set up for them (the company of an invitation it accepted).
  CARRIED_ACROSS_SIGN_IN = %w[current_company_id pending_invitation_token pending_template_install
                              pending_bitbucket_connect pending_marketplace_proposal
                              pending_mcp_authorization].freeze

  # Login continuation for a template install started as a guest (design §7.1).
  # Only the template and the version the guest saw are kept; the route back is
  # built here, so there is no return_to parameter to point somewhere else.
  PENDING_TEMPLATE_INSTALL_KEY = :pending_template_install
  TEMPLATE_NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  def remember_pending_template_install(namespace:, slug:, version:)
    session[PENDING_TEMPLATE_INSTALL_KEY] = { "namespace" => namespace.to_s, "slug" => slug.to_s, "version" => version.to_i }
  end

  # Login continuation for a Bitbucket Connect opened as a guest. The pairing
  # itself never reaches the server — it rides in the link's fragment and waits
  # in the tab's sessionStorage — so only the way back is kept here.
  PENDING_BITBUCKET_CONNECT_KEY = :pending_bitbucket_connect

  def remember_pending_bitbucket_connect
    session[PENDING_BITBUCKET_CONNECT_KEY] = true
  end

  # Login continuation for an administrator who proved their address on a
  # Marketplace proposal link: the request is waiting on their workspace's
  # Billing page. The link does not sign them in (see
  # Web::MarketplaceProposalsController#administrator_at), so the way to the
  # request is kept here and taken by whichever sign-in they complete.
  PENDING_MARKETPLACE_PROPOSAL_KEY = :pending_marketplace_proposal

  def remember_pending_marketplace_proposal(company)
    session[PENDING_MARKETPLACE_PROPOSAL_KEY] = company.id
    session[:current_company_id] = company.id
  end

  # Login continuation for an MCP client's authorization request (Aixle's own
  # OAuth server): only parameters MCPAuth::AuthorizationRequest already
  # accepted are kept, and the way back is always the authorize screen, which
  # checks them again.
  PENDING_MCP_AUTHORIZATION_KEY = :pending_mcp_authorization

  def remember_pending_mcp_authorization(params)
    session[PENDING_MCP_AUTHORIZATION_KEY] = params.slice(*MCPAuth::AuthorizationRequest::PARAMS)
  end

  def take_pending_mcp_authorization_path
    pending = session.delete(PENDING_MCP_AUTHORIZATION_KEY)
    pending.is_a?(Hash) ? mcp_oauth_authorize_path(pending.slice(*MCPAuth::AuthorizationRequest::PARAMS)) : nil
  end

  # Where a sign-in continues when a guest started something that needed one.
  def take_pending_sign_in_path
    template = take_pending_template_install_path
    bitbucket = bitbucket_connect_path if session.delete(PENDING_BITBUCKET_CONNECT_KEY)
    mcp = take_pending_mcp_authorization_path
    mcp || template || bitbucket || take_pending_marketplace_proposal_path
  end

  # Only for a member of the workspace the request is on: the browser that
  # opened the link is not necessarily the administrator's, and whoever signs
  # in there lands where they always do.
  def take_pending_marketplace_proposal_path
    company_id = session.delete(PENDING_MARKETPLACE_PROPOSAL_KEY)
    return nil if company_id.nil? || current_company&.id != company_id

    company_settings_billing_path
  end

  def take_pending_template_install_path
    pending = session.delete(PENDING_TEMPLATE_INSTALL_KEY)
    return nil unless pending.is_a?(Hash)

    namespace, slug = pending.values_at("namespace", "slug").map(&:to_s)
    return nil unless namespace.match?(TEMPLATE_NAME_FORMAT) && slug.match?(TEMPLATE_NAME_FORMAT)

    new_company_template_install_path(namespace: namespace, slug: slug, version: pending["version"].to_i)
  end

  # A new session for every sign-in: the old one (and its CSRF token) is reset,
  # and the sign-in is a UserSession row the server can end.
  def sign_in(user, provider: nil, impersonator: nil)
    carried = session.to_hash.slice(*CARRIED_ACROSS_SIGN_IN)
    current_user_session&.revoke!
    reset_session
    carried.each { |key, value| session[key] = value }

    user_session = UserSession.start!(user: user, impersonator: impersonator, request: request)
    session[:user_session_id] = user_session.id
    session[:user_id] = user.id
    remember_user_session(user_session, user)
    Auth::SessionService.record_proof(user_session, provider) if provider
    user_session
  end

  # A second method proved inside a live session (AD-6). Proofs append: proving
  # one never invalidates another, which is what lets a session satisfy several
  # companies with different policies at once.
  def prove_additional_method(provider)
    return nil unless current_user_session

    Auth::SessionService.record_proof(current_user_session, provider)
    current_user_session
  end

  # Sign in, or — when the same person is already signed in — append this proof
  # to the session they already hold (AD-6). Every method that a signed-in person
  # can complete goes through here, so step-up works the same way whichever one
  # they use.
  def sign_in_or_prove(user, provider:)
    if signed_in? && current_user_session&.user_id == user.id
      prove_additional_method(provider)
    else
      sign_in(user, provider: provider)
    end
  end

  def sign_out
    current_user_session&.revoke!
    reset_session
    remember_user_session(nil, nil)
  end

  def signed_in?
    current_user.present?
  end

  def authenticate_user!
    head(:unauthorized) unless signed_in?
  end

  def authenticate_admin!
    redirect_to(admin_login_path) unless signed_in? && true_user&.super_admin?
  end

  # The signed-in user: the owner of a live UserSession who is still
  # authenticatable (`active` and not soft-deleted), so revoking the session,
  # letting it time out, or suspending the account ends the sign-in.
  def current_user
    current_user_session
    @current_user
  end

  def current_user_session
    return @current_user_session if defined?(@current_user_session)

    candidate = find_user_session
    user = candidate&.live? && candidate.user&.authenticatable? && candidate.user
    unless user
      forget_sign_in if candidate || session[:user_id].present?
      return remember_user_session(nil, nil)
    end

    candidate.touch_if_stale!
    remember_user_session(candidate, user)
  end

  # The membership the current request operates under. Resolution order:
  # 1. the company the path names (/company/<slug>/…) — and only that one: a
  #    company the user is not an active member of resolves to nothing.
  # 2. session[:current_company_id] — but NEVER trusted directly: it must match
  #    one of the user's *active* memberships (revocation invalidates it).
  # 3. Fallback: the user's first active membership (oldest accepted first);
  #    the session is updated so the "last used" company persists.
  # Super admins have no memberships — this returns nil for them (they live in
  # the /admin namespace, which is guarded by `authenticate_admin!` instead).
  def current_membership
    @current_membership ||= resolve_current_membership
  end

  def company_slug_in_path
    request.path_parameters[:company_slug].presence
  end

  # A path naming a company the person cannot enter is not found — not the
  # same page in whichever company they were on. Someone left with no company
  # at all is signed out as before (require_active_membership!).
  def company_in_path_out_of_reach?
    signed_in? && company_slug_in_path.present? && current_membership.nil? && current_user.active_memberships.any?
  end

  # A URL helper fills :company_slug itself: inside /company/<slug> with that
  # slug, so a page's links stay in its company; elsewhere — a sign-in, an
  # OAuth callback, /profile — with the company the request resolved, the one an
  # unscoped link would have opened. `path_params` (not recall) so positional
  # arguments skip the slug — company_project_path(project) — and a route
  # without the segment never gets it as a query parameter.
  def url_options
    options = super
    slug = company_slug_in_path || (signed_in? && current_membership && current_company.slug)
    return options unless slug

    options.merge(path_params: { company_slug: slug }.merge(options.fetch(:path_params, {})))
  end

  # Where the app opens after a sign-in or a detour (step-up, legal, onboarding).
  # Someone in no company — a super admin — has no company page to open, and
  # the root sends them on to theirs.
  def app_home_path
    return root_path unless current_company
    return company_getting_started_path if land_on_getting_started?

    company_projects_path
  end

  def land_on_getting_started?
    Feature.enabled?(:product_tour, company: current_company) && current_membership.getting_started_pending?
  end

  def current_company
    return nil unless current_membership

    # current_membership is an element of User#active_memberships, so :company
    # must be preloaded onto that list before it is dereferenced.
    current_user.active_memberships_with_company
    current_membership.company
  end

  # The admin behind an impersonation — held to the same account-state rule, so
  # suspending or deleting a super admin mid-impersonation ends their /admin access.
  def true_user
    return current_user unless impersonated?

    @true_user ||= User.authenticatable.find_by(id: current_user_session.impersonator_id)
  end

  # The impersonation is a sign-in of its own, recording who started it; the
  # admin's own session ends with it and a fresh one starts when it stops.
  def impersonate_user(user)
    admin = true_user
    sign_in(user, impersonator: admin)
    session[IMPERSONATION_KEY] = admin.id
  end

  def stop_impersonating_user
    admin = true_user if impersonated?
    return sign_out if admin.nil?

    sign_in(admin)
  end

  def impersonated?
    current_user_session&.impersonator_id.present?
  end

  # AD-5: a company stays current only while this session satisfies its
  # effective set. Callers redirect to step-up on false — never a sign-out, and
  # never an unscoped page.
  #
  # An impersonated request passes: the operator's own authentication backs it,
  # and AD-19 already restricts operators to a password.
  def company_auth_policy_satisfied?(company = current_company)
    return true if company.nil? || impersonated?

    @company_auth_policy_satisfied ||= {}
    @company_auth_policy_satisfied.fetch(company.id) do
      @company_auth_policy_satisfied[company.id] = Auth::PolicyResolver.satisfied?(
        company: company, user_session: current_user_session, user: current_user
      )
    end
  end

  # Invitation continuation: an invite token parked before login (see
  # Web::InvitationsController#show) is accepted right after authentication,
  # and the inviting company becomes the current one. The token is only ever
  # honored for the User it was issued to — a mismatched login drops it.
  def accept_pending_invitation(user)
    token = session.delete(:pending_invitation_token)
    return nil if token.blank?

    membership = CompanyMembership.find_by_token_for(:invitation, token)
    return nil unless membership && membership.user_id == user.id

    # Lock + re-check: a concurrent accept (double click, second tab) must
    # degrade to a no-op instead of raising AASM::InvalidTransition.
    accepted = membership.with_lock { membership.may_accept? && membership.accept! }
    return nil unless accepted

    session[:current_company_id] = membership.company_id
    reset_membership_memoization
    # This company's onboarding is its own; re-open it when the accepted role
    # needs an agent this company has none for. Callers route on the
    # membership's onboarding state.
    membership.reopen_onboarding_if_setup_needed!
    membership
  end

  private

  def remember_user_session(user_session, user)
    @current_user_session = user_session
    @current_user = user
    @true_user = nil
    Current.user_session = user_session
    reset_membership_memoization
    user_session
  end

  def find_user_session
    return UserSession.eager_load(:user).find_by(id: session[:user_session_id]) if session[:user_session_id].present?

    adopt_cookie_session if session[:user_id].present?
  end

  # A cookie from before sessions were kept in the database carries only the user
  # id. It becomes a session row on first use, so the change signs nobody out —
  # and from then on it can be ended like any other.
  def adopt_cookie_session
    user = User.authenticatable.find_by(id: session[:user_id])
    return nil unless user&.accepts_sessionless_cookie?

    impersonator = User.authenticatable.find_by(id: session[IMPERSONATION_KEY]) if session[IMPERSONATION_KEY].present?
    adopted = UserSession.start!(user: user, impersonator: impersonator, request: request)
    session[:user_session_id] = adopted.id
    adopted
  end

  def forget_sign_in
    session.delete(:user_session_id)
    session.delete(:user_id)
    session.delete(IMPERSONATION_KEY)
  end

  def resolve_current_membership
    return nil unless current_user

    # User#active_memberships is loaded once per User instance; going through it
    # (instead of a fresh `.active.find_by`) keeps the whole request — policies,
    # project permissions, current-user props — on ONE membership query.
    memberships = current_user.active_memberships
    membership = company_slug_in_path ? membership_named_in_path : last_used_membership(memberships)
    return nil unless membership

    # Persist the resolved company so a fallback (first login, revoked
    # membership) — or the company a tab is on — becomes the "last used" one
    # that the next unscoped link or sign-in opens.
    session[:current_company_id] = membership.company_id if session[:current_company_id] != membership.company_id
    remember_last_company(membership)

    membership
  end

  def membership_named_in_path
    current_user.active_memberships_with_company.find { |m| m.company.slug == company_slug_in_path }
  end

  # Each candidate re-validated against ACTIVE memberships (a revoked company
  # must never resolve, whatever the session says):
  #   1. this session's last company
  #   2. users.last_company_id — the same choice from a PREVIOUS session, so
  #      it survives logout and cookie expiry instead of snapping back to the
  #      oldest membership
  #   3. the oldest accepted membership
  def last_used_membership(memberships)
    find_membership(memberships, session[:current_company_id]) ||
      find_membership(memberships, current_user.last_company_id) ||
      default_membership(memberships)
  end

  def find_membership(memberships, company_id)
    return nil if company_id.blank?

    wanted = company_id.to_i
    memberships.find { |m| m.company_id == wanted }
  end

  # update_column: a bare hint, so it must not bump updated_at (which
  # `broadcasts_to ->(user) { user }` would turn into a cable broadcast on every
  # first request of a session) or run validations.
  def remember_last_company(membership)
    return if current_user.last_company_id == membership.company_id

    current_user.update_column(:last_company_id, membership.company_id)
  end

  # Ruby mirror of CompanyMembership.default_order (accepted_at ASC NULLS FIRST,
  # then id), so the resolved default company matches the SQL ordering exactly.
  def default_membership(memberships)
    memberships.min_by { |m| [ m.accepted_at ? 1 : 0, m.accepted_at || Time.at(0), m.id ] }
  end

  def reset_membership_memoization
    @current_membership = nil
    @current_user&.reload_active_memberships
  end
end
