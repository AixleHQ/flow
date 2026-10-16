# frozen_string_literal: true

module Bitbucket
  module Forge
    # A client on an installation's own app token, for calls made outside any
    # project connection: naming the workspace, checking an administrator,
    # proving the app reaches its repositories before a connection is made.
    module AppClient
      MIN_REMAINING = 60

      module_function

      def for(installation)
        token = installation.usable_token(min_remaining: MIN_REMAINING)
        raise Error::CredentialUnavailable, "The Aixle Flow app has not delivered a usable token for this workspace yet." unless token

        Client.new(credential: Credential.new(token: token, kind: :app))
      end
    end
  end
end
