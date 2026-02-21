# frozen_string_literal: true

# Adds charset=utf-8 to text/* Content-Type headers.
# Ensures correct encoding for static files served from public/ (Shrine FileSystem storage).
module Middleware
  class Utf8ContentType
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      ct = headers["content-type"] || headers["Content-Type"]
      if ct&.start_with?("text/") && !ct.include?("charset")
        headers["content-type"] = "#{ct}; charset=utf-8"
      end

      [status, headers, response]
    end
  end
end
