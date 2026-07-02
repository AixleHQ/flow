module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :current_company
    identified_by :session_id

    def connect
      self.current_user = find_verified_user
      self.current_company = resolve_current_company
      self.session_id = request.params[:session_id] || SecureRandom.uuid
      logger.info "[ActionCable] Connected: user=#{current_user&.id}, session=#{session_id}"
    end

    private

    def find_verified_user
      User.find_by(id: request.session[:user_id])
    end

    # Same resolution rule as AuthConcern#current_membership: the session's
    # company id is only honored when it matches an ACTIVE membership, with a
    # first-active-membership fallback. (Read-only here — no session write.)
    def resolve_current_company
      return nil unless current_user

      memberships = current_user.company_memberships.active
      membership = memberships.find_by(company_id: request.session[:current_company_id]) if request.session[:current_company_id].present?
      membership ||= memberships.default_order.first
      membership&.company
    end
  end
end
