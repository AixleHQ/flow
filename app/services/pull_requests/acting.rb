# frozen_string_literal: true

module PullRequests
  # The person a pull-request write is made as, instead of the connection
  # (docs/design/bitbucket-integration.md §4.12). The token is the person's own for
  # this one call: it stays on the server and is never part of a result, a log line
  # or an error message, so `inspect` and `to_s` leave it out.
  #
  # Who it is (`user_id`) is known up front; the token and login are not. `Acting` runs
  # the block on the first read of either, so a call that is refused or replayed before
  # it reaches the host mints no token. The block returns `{ login:, token: }` and may
  # raise PullRequests::Error; a failed attempt is not remembered. `inspect` and `to_s`
  # never run the block: a log line or an interpolation must not mint a token.
  class Acting
    attr_reader :user_id

    def initialize(user_id:, &resolver)
      @user_id = user_id
      @resolver = resolver
    end

    def login = resolved[:login]
    def token = resolved[:token]

    def inspect
      login = " login=#{@resolved[:login].inspect}" if @resolved
      "#<#{self.class.name} user_id=#{user_id}#{login}>"
    end
    alias_method :to_s, :inspect

    private

    def resolved
      @resolved ||= @resolver.call
    end
  end
end
