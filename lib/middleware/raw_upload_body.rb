# frozen_string_literal: true

# Development/test only.
#
# @uppy/aws-s3 v6 uploads a file as a raw PUT whose body is the file's bytes and whose
# Content-Type is the file's own type. In production that request goes straight to S3, but
# locally it is served by Api::V1::AssetsController#upload — and ActionDispatch parses a
# request body whenever its content type has a registered parser. A `.json` asset would
# therefore be JSON-parsed before the action ever runs, turning every such file that isn't
# itself valid JSON into a 400 (and reading a large one into memory for nothing).
#
# Parsing is triggered by ActionController's own instrumentation, ahead of any callback, so
# there is no hook inside the controller that can opt out. Rewriting the content type to
# application/octet-stream — which has no registered parser — is the seam that works, and
# it costs nothing downstream: the action streams request.body into cache storage, and the
# mime type Shrine records is re-derived from the bytes by determine_mime_type.
module Middleware
  class RawUploadBody
    PATH_PREFIX = "/api/v1/assets/upload/"

    def initialize(app)
      @app = app
    end

    def call(env)
      if env["REQUEST_METHOD"] == "PUT" && env["PATH_INFO"].to_s.start_with?(PATH_PREFIX)
        env["CONTENT_TYPE"] = "application/octet-stream"
      end

      @app.call(env)
    end
  end
end
