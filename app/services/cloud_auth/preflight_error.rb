# frozen_string_literal: true

module CloudAuth
  # Raised at session-start when a user's cloud connection exists but cannot mint
  # credentials. Carries the same entry shape as Oauth::PreflightError (`name` +
  # `connect_url`) so the API renders one `reauth_required` list and the frontend needs
  # no second CTA.
  #
  # Deliberately not an Oauth error: nothing here involves the OAuth token broker.
  class PreflightError < StandardError
    attr_reader :connections

    def initialize(connections)
      @connections = connections
      super("Reconnect required for #{connections.size} cloud connection(s) before launching")
    end
  end
end
