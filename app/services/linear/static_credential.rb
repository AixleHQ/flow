# frozen_string_literal: true

module Linear
  # A credential in hand, for the requests made while a connection is set up.
  class StaticCredential
    def self.api_key(key) = new("Authorization" => key.to_s)
    def self.bearer(token) = new("Authorization" => "Bearer #{token}")

    def initialize(headers)
      @headers = headers
    end

    def authorization_headers = @headers

    def invalidate!
      raise Trackers::Error.new("Linear refused this credential", code: "not_authorized")
    end
  end
end
