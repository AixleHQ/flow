# frozen_string_literal: true

module PullRequests
  # The person a pull-request write is made as, instead of the connection
  # (docs/design/bitbucket-integration.md §4.12). The token is the person's own for
  # this one call: it stays on the server and is never part of a result, a log line
  # or an error message, so `inspect` leaves it out.
  #
  # Who it is (`user_id`) is known up front; the token and login are not. Given a block,
  # `Acting` runs it on the first read of either, so a call that is refused or replayed
  # before it reaches the host mints no token. The block returns `{ login:, token: }`
  # and may raise PullRequests::Error; a failed attempt is not remembered.
  class Acting
    attr_reader :user_id

    def initialize(user_id:, login: nil, token: nil, &resolver)
      @user_id = user_id
      @login = login
      @token = token
      @resolver = resolver
    end

    def login = resolved[:login]
    def token = resolved[:token]

    def inspect = "#<#{self.class.name} user_id=#{user_id} login=#{login.inspect}>"
    alias_method :to_s, :inspect

    private

    def resolved
      @resolved ||= @resolver ? @resolver.call : { login: @login, token: @token }
    end
  end
end
