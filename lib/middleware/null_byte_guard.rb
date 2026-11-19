# frozen_string_literal: true

# Answers 400 to a request whose path or query string carries a NUL byte.
# Postgres rejects NUL in a text bind, so a lookup by such a path param
# (`/webhooks/in/%00`) raised ArgumentError and answered 500.
module Middleware
  class NullByteGuard
    NUL = /%00|\0/i

    def initialize(app)
      @app = app
    end

    def call(env)
      return bad_request if env["PATH_INFO"].to_s.match?(NUL) || env["QUERY_STRING"].to_s.match?(NUL)

      @app.call(env)
    end

    private

    def bad_request
      [ 400, { "content-type" => "text/plain" }, [ "Bad Request" ] ]
    end
  end
end
