module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :session_id

    def connect
      self.current_user = find_verified_user
      self.session_id = request.params[:session_id] || SecureRandom.uuid
      logger.info "[ActionCable] Connected: user=#{current_user&.id}, session=#{session_id}"
    end

    private

    def find_verified_user
      User.find_by(id: request.session[:user_id])
    end
  end
end
