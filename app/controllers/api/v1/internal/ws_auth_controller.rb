# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Traefik ForwardAuth endpoint for terminal WebSocket authorization
      #
      # Traefik calls this endpoint before proxying WebSocket connections to containers.
      # We verify that:
      #   1. User is authenticated (via session cookie)
      #   2. User owns the requested terminal session
      #   3. Terminal session is in a valid state (running)
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
      class WsAuthController < Api::V1::ApplicationController
        # Skip default authentication - we handle it manually with proper logging
        skip_before_action :authenticate_user!

        def show
          route_token = extract_route_token
          unless route_token
            Rails.logger.debug("[WsAuth] No route_token found in request")
            return head :bad_request
          end

          terminal_session = TerminalSession.find_by(route_token: route_token)
          unless terminal_session
            Rails.logger.debug("[WsAuth] Session not found for route_token: #{route_token}")
            return head :not_found
          end

          unless current_user
            Rails.logger.debug("[WsAuth] No authenticated user for route_token #{route_token}")
            return head :unauthorized
          end

          unless terminal_session.user_id == current_user.id
            Rails.logger.warn("[WsAuth] User #{current_user.id} tried to access session #{terminal_session.id} owned by #{terminal_session.user_id}")
            return head :forbidden
          end

          unless terminal_session.state.in?(%w[ready])
            Rails.logger.debug("[WsAuth] Session #{terminal_session.id} not running (state: #{terminal_session.state})")
            return head :forbidden
          end

          # Pass user info to downstream (optional)
          response.set_header("X-User-Id", current_user.id.to_s)
          response.set_header("X-Session-Id", terminal_session.id.to_s)

          head :ok
        end

        private

        # Extract route_token from X-Forwarded-Uri header (set by Traefik ForwardAuth)
        # Example: /t/abc123def456/tty/ws → abc123def456
        def extract_route_token
          forwarded_uri = request.headers["X-Forwarded-Uri"]
          return nil unless forwarded_uri

          # Match /t/{route_token}/tty or /t/{route_token}/fs
          match = forwarded_uri.match(%r{/t/([a-f0-9]+)/})
          match&.[](1)
        end
      end
    end
  end
end
