module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      self.session_id = request.params[:session_id] || SecureRandom.uuid
      logger.info "[ActionCable] Connected: #{session_id}"
    end
  end
end
