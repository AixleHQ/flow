# frozen_string_literal: true

module PullRequests
  # The person a pull-request write is made as, instead of the connection
  # (docs/design/bitbucket-integration.md §4.12). The token is the person's own for
  # this one call: it stays on the server and is never part of a result, a log line
  # or an error message, so `inspect` leaves it out.
  class Acting
    attr_reader :user_id, :login, :token

    def initialize(user_id:, login:, token:)
      @user_id = user_id
      @login = login
      @token = token
    end

    def inspect = "#<#{self.class.name} user_id=#{user_id} login=#{login.inspect}>"
    alias_method :to_s, :inspect
  end
end
