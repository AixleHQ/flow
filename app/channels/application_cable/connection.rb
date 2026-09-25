# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :current_company
    identified_by :session_id

    def connect
      self.current_user = find_verified_user || reject_unauthorized_connection
      self.current_company = resolve_current_company
      self.session_id = request.params[:session_id] || SecureRandom.uuid
      logger.info "[ActionCable] Connected: user=#{current_user&.id}, session=#{session_id}"
    end

    private

    # The same rule as AuthConcern#current_user: a live UserSession of an
    # authenticatable user. A cookie from before database sessions carries only the
    # user id, and the next page load turns it into a session row.
    def find_verified_user
      user_session_id = request.session[:user_session_id]
      return sessionless_cookie_user if user_session_id.blank?

      user_session = UserSession.find_by(id: user_session_id)
      user_session&.live? ? User.authenticatable.find_by(id: user_session.user_id) : nil
    end

    def sessionless_cookie_user
      user = User.authenticatable.find_by(id: request.session[:user_id])
      user if user&.accepts_sessionless_cookie?
    end

    # Same resolution rule as AuthConcern#current_membership — the session's
    # company, then users.last_company_id, then the oldest accepted membership,
    # each honored only while it is an ACTIVE membership. (Read-only here.)
    def resolve_current_company
      return nil unless current_user

      memberships = current_user.company_memberships.active
      membership = memberships.find_by(company_id: request.session[:current_company_id]) if request.session[:current_company_id].present?
      membership ||= memberships.find_by(company_id: current_user.last_company_id) if current_user.last_company_id.present?
      membership ||= memberships.default_order.first
      membership&.company
    end
  end
end
