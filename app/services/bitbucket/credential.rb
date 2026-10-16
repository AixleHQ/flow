# frozen_string_literal: true

module Bitbucket
  # What a request authenticates with. `kind` decides the git username:
  # Bitbucket refuses an API token under `x-token-auth`, and an access token or
  # the Forge app token under anything else.
  class Credential
    KINDS = %i[app access_token api_token].freeze

    attr_reader :token, :kind

    def initialize(token:, kind:, refresher: nil)
      raise ArgumentError, "unknown Bitbucket credential kind #{kind.inspect}" unless KINDS.include?(kind)

      @token = token
      @kind = kind
      @refresher = refresher
    end

    def git_username = kind == :api_token ? "x-bitbucket-api-token-auth" : "x-token-auth"

    def authorization_headers = { "Authorization" => "Bearer #{token}" }

    # A different credential worth one retry after a 401, or nil. Only the app
    # can have one: a newer token may have landed since this one was read.
    def refresh = @refresher&.call

    def inspect = "#<#{self.class.name} kind=#{kind}>"
  end
end
