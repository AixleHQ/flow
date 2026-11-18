# frozen_string_literal: true

module MCPAuth
  # The client_id of a token or revocation request. A public client puts it in
  # the body; some send it as the user part of HTTP Basic (client_secret_basic
  # with an empty secret) even when registered as public.
  module ClientAuthentication
    private

    def presented_client_id
      return params[:client_id].presence&.to_s if params[:client_id].present?

      header = request.authorization.to_s
      return nil unless header.start_with?("Basic ")

      user, = Base64.decode64(header.delete_prefix("Basic ")).split(":", 2)
      user.present? ? CGI.unescape(user) : nil
    end
  end
end
