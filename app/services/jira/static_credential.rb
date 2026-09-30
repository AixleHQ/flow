# frozen_string_literal: true

module Jira
  # A token in hand, for the requests made while a connection is being set up.
  class StaticCredential
    def initialize(access_token)
      @access_token = access_token
    end

    def authorization_headers
      { "Authorization" => "Bearer #{@access_token}" }
    end

    def invalidate!
      raise Error.new("Atlassian refused the token", code: "not_authorized", status: 401)
    end
  end
end
