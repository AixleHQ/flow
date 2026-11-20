# frozen_string_literal: true

module Runners
  # The ticket a machine opens the interactive tunnel with
  # (docs/design/agent-runtimes/runner-relay.md §3.1; runner/protocol/PROTOCOL.md
  # §5.11 and §8): `POST /runner/v1/tunnel-ticket`, authenticated like any endpoint
  # of the gateway, answers one. The runner presents it once as
  # `Authorization: Bearer <ticket>` on `GET /runner/v1/tunnel`, which the
  # `runner-relay` service serves. The access token never reaches the relay.
  #
  #   issued = Runners::TunnelTicket.issue(environment: environment)
  #   issued.ticket       # "artun_<header>.<claims>.<signature>"
  #   issued.expires_at   # 60 seconds from now
  #
  # The ticket is `artun_` + a standard compact JWT (HS256, the `jwt` gem), signed under
  # `Settings.runners.relay.ticket_key`. The relay verifies it with a JWT library too
  # (runner-relay/internal/ticket), so neither end has signing code of its own. The prefix
  # is for secret scanners; it is stripped before decoding. The claims:
  #
  #   {"v":1,"e":<environment id>,"r":<runner id>,"s":<session id or null>,"jti":"…","exp":<unix seconds>}
  #
  # `s` is the session that holds the machine when the ticket is minted: the relay
  # puts it in its HELLO, and never believes the runner about it. A machine that holds
  # no session gets no ticket (`no_session`), so an idle machine opens no connection.
  #
  # The relay refuses a ticket past `exp` (with 5 seconds of tolerance) and a second
  # use of one `jti`; both are its own checks (runner-relay/internal/ticket).
  module TunnelTicket
    PREFIX = "artun_"
    ALGORITHM = "HS256"
    # The gem leaves `typ` out; the ticket says what it is, as the design (§3.1) shows.
    HEADER = { typ: "JWT" }.freeze
    VERSION = 1
    LIFETIME = 60.seconds
    # What a runner is told in the check-in's `config.tunnel.mode` (Settings
    # `runners.relay.tunnel_mode`): connect while the machine holds a session.
    MODES = %w[session].freeze

    Issued = Data.define(:ticket, :expires_at)

    module_function

    # Whether tickets can be minted: the platform has a key to sign them with. The relay
    # is then (or will be) deployed with the same key. Blank, no ticket is minted.
    def configured?
      ticket_key.present?
    end

    # Whether the check-in tells runners to connect (`config.tunnel`): the key is set and
    # so is a mode. Off by default, so nothing changes for a machine until the relay is
    # deployed and the deployment turns it on: a runner asks for a ticket only after the
    # check-in said so.
    def enabled?
      configured? && MODES.include?(mode)
    end

    def mode
      Settings.runners.relay.tunnel_mode.to_s
    end

    def public_path
      Settings.runners.relay.public_path.to_s
    end

    # What the check-in tells the runner (`config.tunnel`), or nil when the tunnel is off.
    def config
      return unless enabled?

      { "mode" => mode, "path" => public_path }
    end

    # A ticket for the machine, which must hold a session. Raises Credentials::Refused:
    # `not_found` when the platform has no ticket key, `no_session` when the machine
    # holds none.
    def issue(environment:, now: Time.current)
      unless configured?
        raise Credentials::Refused.new("not_found", "The platform does not offer the interactive tunnel.")
      end

      unless environment.busy?
        raise Credentials::Refused.new("no_session", "This machine holds no session, so it opens no tunnel.")
      end

      expires_at = now + LIFETIME
      claims = {
        v: VERSION, e: environment.id, r: environment.runner_id, s: environment.current_session_id,
        jti: SecureRandom.urlsafe_base64(16), exp: expires_at.to_i
      }
      Issued.new(ticket: "#{PREFIX}#{JWT.encode(claims, ticket_key, ALGORITHM, HEADER)}", expires_at: expires_at.utc)
    end

    def ticket_key
      Settings.runners.relay.ticket_key.to_s
    end
    private_class_method :ticket_key
  end
end
