# frozen_string_literal: true

require "net/http"

module RunnerGateway
  module V1
    # `ANY /runner/v1/proxy/:route/*` (docs/design/agent-runtimes/DESIGN.md
    # §6.6, §6.9.3; runner/protocol/PROTOCOL.md §5.8): the callback proxy's
    # end at the platform. A runner session's agent calls its local proxy on
    # 127.0.0.1, which relays to the host runner, which adds the environment's
    # access token and calls this route. The gateway:
    #
    # 1. authenticates the environment credential, as every endpoint does;
    # 2. passes only an allow-listed route, method and path
    #    (Runners::Proxy::ROUTES), else `404 route_not_allowed`;
    # 3. checks that the session key in the forwarded request belongs to the
    #    session that holds this environment now (Runners::Proxy.holder), else
    #    `403 session_not_on_environment`;
    # 4. forwards the request unchanged, plus `X-Aixle-Runner-Environment`, to
    #    the internal endpoint over HTTP, and streams the answer back as it
    #    comes, because MCP's streamable HTTP may hold a response open.
    #
    # The body is the agent's, not the gateway's, so it has no JSON Schema
    # (task 8b, decision 9). Every refusal of this route, the common ones of
    # §3 included, carries `X-Aixle-Runner-Refusal: <error>`, so the runner
    # tells the gateway's own refusal from the internal endpoint's answer,
    # which it passes on as it is.
    class ProxiesController < ApplicationController
      include ActionController::Live
      include ActionController::ParameterEncoding

      # The path is the agent's: Rails would refuse a path parameter that is
      # not valid UTF-8 with a 400 of its own, before this controller could
      # refuse it as `route_not_allowed`. Left binary, it reaches
      # Runners::Proxy::Route#allows?, which decodes it strictly. An API
      # controller lacks ParameterEncoding, and its table is set up only for
      # the subclasses of the class that includes it, so this one sets it up.
      setup_param_encode
      skip_parameter_encoding :forward

      REFUSAL_HEADER = "X-Aixle-Runner-Refusal"
      ENVIRONMENT_HEADER = "X-Aixle-Runner-Environment"
      METHODS = {
        "GET" => Net::HTTP::Get, "HEAD" => Net::HTTP::Head, "POST" => Net::HTTP::Post, "DELETE" => Net::HTTP::Delete
      }.freeze
      # Not forwarded either way: hop-by-hop headers, the gateway's own and
      # the bearer the runner presented, which is the environment's token.
      # The internal endpoints take their keys in headers of their own.
      DROPPED_REQUEST_HEADERS = %w[
        authorization host connection keep-alive proxy-authorization proxy-connection te trailer
        transfer-encoding upgrade content-length version accept-encoding
      ].freeze
      DROPPED_RESPONSE_HEADERS = %w[
        connection keep-alive proxy-authenticate proxy-connection te trailer transfer-encoding upgrade content-length
      ].freeze
      OPEN_TIMEOUT = 5
      # MCP's streamable HTTP holds a tool call's response until the tool
      # ends, and a GET stream between events. Net::HTTP applies it to each
      # read, so it cuts an answer that sends no data for that long, not a
      # long one that keeps sending (PROTOCOL.md §5.8). It stays finite: a
      # silent upstream would otherwise hold a gateway thread for good, even
      # after the runner has gone. A longer tool is asynchronous
      # (`read_tool_result`).
      READ_TIMEOUT = 900
      UPSTREAM_ERRORS = [
        SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      ].freeze

      before_action { authenticate(:access) }

      # The route comes from the path alone: `params` would parse the agent's
      # body, which is not the gateway's.
      def forward
        route = Runners::Proxy.route(request.path_parameters[:route])
        below = route && below_route(route)
        unless route&.allows?(request.request_method, below)
          return refuse(:not_found, "route_not_allowed",
                        "The callback proxy does not forward #{request.request_method} to this route.")
        end

        environment = @credential.runner_environment
        if session_holder(route, environment).nil?
          return refuse(:forbidden, "session_not_on_environment",
                        "The request carries no key of the session this machine runs now.")
        end

        stream(Runners::Proxy.upstream_url(route, below, request.query_string), environment)
      end

      private

      # The service takes values, not the request: the session id and the
      # route's key are read from the headers here.
      def session_holder(route, environment)
        header = Runners::Proxy.key_header(route)
        Runners::Proxy.holder(route, environment,
                              session_id: request.headers["X-Session-Id"],
                              key: header && request.headers[header])
      end

      def refuse(status, error, message)
        response.set_header(REFUSAL_HEADER, error)
        super
      end

      # The path below the route, as it was sent (percent-encoded).
      def below_route(route)
        request.path.delete_prefix("/runner/v1/proxy/#{route.name}").delete_prefix("/")
      end

      def stream(uri, environment)
        outbound = METHODS.fetch(request.request_method).new(uri.request_uri)
        forwarded_headers.each { |name, value| outbound[name] = value }
        outbound[ENVIRONMENT_HEADER] = environment.id.to_s
        # The agent's own encoding, or none: Net::HTTP would otherwise ask for
        # gzip and decode it, which changes the answer.
        outbound["Accept-Encoding"] = request.headers["Accept-Encoding"].presence || "identity"
        body = request.body&.read
        outbound.body = body if body.present?

        # The forward may stream for up to READ_TIMEOUT and needs no database:
        # the connection goes back to the pool for it, as the ops long-poll
        # does (Runners::Operations.poll).
        ActiveRecord::Base.connection_pool.release_connection
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(outbound) do |upstream|
            response.status = upstream.code.to_i
            dropped = DROPPED_RESPONSE_HEADERS + connection_tokens(upstream["Connection"])
            upstream.each_header do |name, value|
              response.headers[name] = value unless dropped.include?(name.downcase)
            end
            upstream.read_body { |chunk| response.stream.write(chunk) }
          end
        end
        response.stream.close
      rescue ActionController::Live::ClientDisconnected
        # The host runner cut the call: its session stopped, or its relay closed.
        Rails.logger.info("[RunnerGateway::Proxy] environment #{environment.id}: the runner disconnected during the answer")
        response.stream.close
      rescue *UPSTREAM_ERRORS => e
        Rails.logger.warn("[RunnerGateway::Proxy] environment #{environment.id}: #{uri.host}:#{uri.port}: #{e.class}: #{e.message}")
        if response.committed?
          response.stream.close
        else
          refuse(:bad_gateway, "upstream_unavailable", "The platform's endpoint for this route did not answer.")
        end
      end

      # The request's headers as the agent sent them, less the dropped ones
      # and the ones its `Connection` header nominates (RFC 9110 §7.6.1).
      def forwarded_headers
        nominated = connection_tokens(request.headers["Connection"])
        request.headers.env.each_with_object({}) do |(key, value), headers|
          name = if key.start_with?("HTTP_")
            key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
          elsif key == "CONTENT_TYPE"
            "Content-Type"
          end
          next if name.nil? || value.blank?
          next if DROPPED_REQUEST_HEADERS.include?(name.downcase) || nominated.include?(name.downcase)
          next if name.downcase.start_with?("x-aixle-runner-")

          headers[name] = value
        end
      end

      # The field names a `Connection` header nominates, lowercased: they are
      # hop-by-hop, as the fixed ones are, and never forwarded.
      def connection_tokens(value)
        value.to_s.split(",").map { |token| token.strip.downcase }.compact_blank
      end
    end
  end
end
