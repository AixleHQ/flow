# frozen_string_literal: true

module AuthConcern
  extend ActiveSupport::Concern

  IMPERSONATION_KEY = "true_user_id"

  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session[:user_id] = nil
    session.delete(:current_company_id)
    session.delete(:pending_invitation_token)
    @current_user = nil
    reset_membership_memoization
  end

  def signed_in?
    session[:user_id].present? && current_user.present?
  end

  def authenticate_user!
    head(:unauthorized) unless signed_in?
  end

  def authenticate_admin!
    redirect_to("/login") unless signed_in? && true_user.super_admin?
  end

  def current_user
    # `active` is the AASM account-state scope; `not_deleted` additionally
    # excludes soft-deleted users so an admin-deleted account cannot stay
    # authenticated on an existing session.
    @current_user ||= User.active.not_deleted.find_by(id: session[:user_id])
  end

  # The membership the current request operates under. Resolution order:
  # 1. session[:current_company_id] — but NEVER trusted directly: it must match
  #    one of the user's *active* memberships (revocation invalidates it).
  # 2. Fallback: the user's first active membership (oldest accepted first);
  #    the session is updated so the "last used" company persists.
  # Super admins have no memberships — this returns nil for them (they live in
  # the /admin namespace, which is guarded by `authenticate_admin!` instead).
  def current_membership
    @current_membership ||= resolve_current_membership
  end

  def current_company
    return nil unless current_membership

    # current_membership is an element of User#active_memberships, so :company
    # must be preloaded onto that list before it is dereferenced.
    current_user.active_memberships_with_company
    current_membership.company
  end

  def true_user
    @true_user ||= User.find_by(id: session[IMPERSONATION_KEY] || session[:user_id])
  end

  def impersonate_user(user)
    session[IMPERSONATION_KEY] = true_user.id
    @current_user = nil
    reset_membership_memoization
    sign_in(user)
  end

  def stop_impersonating_user
    true_user_id = session.delete(IMPERSONATION_KEY)
    true_user = User.find(true_user_id)
    @current_user = nil
    reset_membership_memoization

    sign_in(true_user)
  end

  def impersonated?
    session[IMPERSONATION_KEY].present?
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
    membership
  end

  private

  def resolve_current_membership
    return nil unless current_user

    # User#active_memberships is loaded once per User instance; going through it
    # (instead of a fresh `.active.find_by`) keeps the whole request — policies,
    # project permissions, current-user props — on ONE membership query.
    memberships = current_user.active_memberships
    if session[:current_company_id].present?
      wanted = session[:current_company_id].to_i
      membership = memberships.find { |m| m.company_id == wanted }
    end
    membership ||= default_membership(memberships)

    # Persist the resolved company so a fallback (first login, revoked
    # membership) becomes the "last used" company on subsequent requests.
    session[:current_company_id] = membership.company_id if membership && session[:current_company_id] != membership.company_id

    membership
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
