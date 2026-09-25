# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Traefik ForwardAuth endpoint for terminal WebSocket authorization
      #
      # Traefik calls this endpoint before proxying WebSocket connections to containers.
      # We verify that:
      #   1. User is authenticated (via session cookie)
      #   2. User may reach the session's container — they own it, or they can
      #      reach its project AND its owner shares this phase of their sessions
      #      (TerminalSession#container_accessible_by?)
      #   3. Terminal session is in a valid state (running)
      #
      # This is the gate that actually protects the container: the route token in
      # the URL is not a secret Traefik checks anything against, so a token that
      # leaked once would otherwise be a permanent key.
      #
      # Request headers from Traefik:
      #   X-Forwarded-Uri: /t/{route_token}/tty/ws (original request path)
      #   Cookie: _aixle_session=xxx (user session)
      #
      # Response:
      #   200 OK - allow proxy
      #   401 Unauthorized - no user session
      #   403 Forbidden - user doesn't own session or session not running
      #   404 Not Found - session doesn't exist
      #
      class WsAuthController < Api::V1::Internal::ApplicationController
        # Cookies the container's own processes need (OpenVSCode keeps its
        # connection token in `vscode-tkn`). Nothing else the browser holds for
        # this host may reach the pod: whatever listens there is controlled by
        # the agent, and the browser's cookies include the Rails session.
        CONTAINER_COOKIE = /\Avscode-[\w-]+\z/

        # What only the session's owner may open: the writable terminal and the
        # IDE are both a shell in a container that holds the owner's agent login,
        # git token and vending keys. Everyone else the session is shared with
        # gets the read-only terminal (`view`) and the read-only file server.
        OWNER_ONLY_SURFACES = %w[tty ide].freeze

        def show
          route_token, surface = extract_route
          unless route_token
            Rails.logger.debug("[WsAuth] No route_token found in request")
            return head :bad_request
          end

          terminal_session = TerminalSession.find_by(route_token: route_token)
          unless terminal_session
            Rails.logger.debug("[WsAuth] Session not found for route_token: #{route_token}")
            return head :not_found
          end

          viewer = requesting_user(terminal_session)
          unless viewer
            Rails.logger.debug("[WsAuth] No authenticated user for route_token #{route_token}")
            return head :unauthorized
          end

          unless terminal_session.container_accessible_by?(viewer)
            Rails.logger.warn("[WsAuth] User #{viewer.id} tried to access session #{terminal_session.id} owned by #{terminal_session.user_id}")
            return head :forbidden
          end

          if OWNER_ONLY_SURFACES.include?(surface) && terminal_session.user_id != viewer.id
            Rails.logger.warn("[WsAuth] User #{viewer.id} refused the #{surface} of session #{terminal_session.id}, owned by #{terminal_session.user_id}")
            return head :forbidden
          end

          unless terminal_session.state.in?(%w[ready])
            Rails.logger.debug("[WsAuth] Session #{terminal_session.id} not running (state: #{terminal_session.state})")
            return head :forbidden
          end

          # Pass user info to downstream (optional)
          response.set_header("X-User-Id", viewer.id.to_s)
          response.set_header("X-Session-Id", terminal_session.id.to_s)
          forward_container_cookies
          issue_sandbox_cookie(viewer, terminal_session) if @ticket_from_url

          head :ok
        end

        private

        # Containers served from a host of their own receive none of the app's
        # cookies, so the viewer is named by a ContainerTicket — in the URL the app
        # handed out, or in the cookie this gate traded it for. A frame reloaded
        # after its URL's pass expired still carries that pass, so an expired one
        # falls through to the cookie. On the app's own host the session cookie
        # still works.
        def requesting_user(terminal_session)
          ticket = forwarded_query[ContainerTicket::PARAM]
          @url_ticket = ContainerTicket.verify(ticket, session: terminal_session) if ticket.present?
          if @url_ticket
            @ticket_from_url = true
            return User.authenticatable.find_by(id: @url_ticket["u"])
          end

          cookie = request.cookies[ContainerTicket::COOKIE]
          return ContainerTicket.user_for(cookie, session: terminal_session) if cookie.present?

          current_user
        end

        # Handed to the browser by Traefik (`addAuthCookiesToResponse` on the
        # terminal-auth middleware), on the sandbox host only and scoped to this
        # session's routes. Partitioned, because the sandbox is framed by the app.
        def issue_sandbox_cookie(viewer, terminal_session)
          value = ContainerTicket.issue(user: viewer, session: terminal_session, ttl: ContainerTicket::COOKIE_TTL,
                                        user_session_id: @url_ticket&.dig("us"))
          response.set_header("Set-Cookie",
            "#{ContainerTicket::COOKIE}=#{value}; Path=/t/#{terminal_session.route_token}/; " \
            "Max-Age=#{ContainerTicket::COOKIE_TTL.to_i}; HttpOnly; Secure; SameSite=None; Partitioned")
        end

        def forwarded_query
          query = URI.parse(request.headers["X-Forwarded-Uri"].to_s).query
          query.present? ? Rack::Utils.parse_query(query) : {}
        rescue URI::InvalidURIError
          {}
        end

        # The terminal-auth middleware lists Cookie and Authorization in
        # authResponseHeadersRegex, so Traefik deletes both from the proxied
        # request and substitutes whatever this response carries. Answering with
        # only the container's own cookies is what keeps the session cookie out
        # of the pod; answering with no Cookie header forwards none.
        def forward_container_cookies
          pairs = request.headers["Cookie"].to_s.split(";").map(&:strip).select do |pair|
            pair.split("=", 2).first.to_s.match?(CONTAINER_COOKIE)
          end
          response.set_header("Cookie", pairs.join("; ")) if pairs.any?
        end

        # The route token and the surface it is for, from the X-Forwarded-Uri
        # Traefik sets: /t/abc123def456/tty/ws → ["abc123def456", "tty"]. An
        # unrecognised surface is treated as owner-only.
        def extract_route
          match = request.headers["X-Forwarded-Uri"].to_s.match(%r{\A/t/([a-f0-9]+)/([a-z]+)})
          return [ nil, nil ] unless match

          surface = match[2]
          [ match[1], surface.in?(%w[tty ide fs view]) ? surface : "tty" ]
        end
      end
    end
  end
end
