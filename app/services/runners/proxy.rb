# frozen_string_literal: true

module Runners
  # The callback proxy (docs/design/agent-runtimes/DESIGN.md §6.6, §6.9.3;
  # runner/protocol/PROTOCOL.md §5.6). An agent on a runner cannot reach the
  # platform's internal address, so it calls a proxy on 127.0.0.1 next to it:
  # the proxy sidecar of its container, or with `network: host` the host
  # runner's own listener. That proxy relays to the host runner, which adds
  # the environment credential and calls `ANY /runner/v1/proxy/:route/*` on
  # the gateway, which forwards the request to the internal endpoint.
  #
  # This module is the platform's half of the contract:
  #
  # - local_url: the address a runner session is given for a callback
  #   (RunnerRuntime#callback_url), `http://127.0.0.1:<port>/<route>`;
  # - ROUTES: the allow-list, decision 7 of task 8b; nothing else passes;
  # - holder: whether a forwarded request carries a session key of the
  #   session that holds the environment now;
  # - upstream_url: where the gateway forwards a route to.
  module Proxy
    LOOPBACK = "127.0.0.1"
    # The sidecar's port, a constant of PROTOCOL.md: outside the agent
    # image's own ports (7681, 7682, 4040, 4041, 8443, 8888).
    PORT = 7690
    # With `network: host` the agent shares the machine's network namespace,
    # so the host runner listens on the machine's 127.0.0.1, and every
    # session needs a port of its own there: a port in
    # HOST_PORT_BASE...HOST_PORT_BASE + HOST_PORT_SPAN, from the session's
    # id. The port has to be known when the strategy builds the container's
    # environment, before the session takes a machine, so it cannot come
    # from the machine.
    HOST_PORT_BASE = 20_000
    HOST_PORT_SPAN = 10_000

    # One allow-listed route: its path segment, the callback it stands for
    # (ContainerRuntime::CallbackUrls), the methods it takes, whether a path
    # below it passes (`prefix`, the first segment it must start with) and
    # the session key it is checked by.
    Route = Data.define(:name, :callback, :methods, :prefix, :key) do
      # Whether a request of this method, with this path below the route (as
      # it was sent, percent-encoded), passes. A route without a prefix takes
      # no path below it, and no segment may lead out of the prefix.
      def allows?(method, path)
        return false unless methods.include?(method.to_s.upcase)

        path = path.to_s
        return path.empty? if prefix.nil?

        segments = path.split("/", -1).map { |segment| CGI.unescape(segment) }
        path.start_with?(prefix) && segments.none? { |segment| segment.empty? || %w[. ..].include?(segment) || segment.include?("/") }
      end
    end

    ROUTES = [
      Route.new(name: "mcp", callback: :mcp, methods: %w[GET POST DELETE], prefix: nil, key: :mcp),
      Route.new(name: "agent-credentials", callback: :agent_credential_sync, methods: %w[POST], prefix: nil, key: :agent),
      Route.new(name: "agent-credentials-refresh", callback: :agent_credential_refresh, methods: %w[POST], prefix: nil,
                key: :agent),
      Route.new(name: "git-credentials", callback: :git_credentials, methods: %w[POST], prefix: nil, key: :git),
      Route.new(name: "azure-git-credentials", callback: :azure_git_credentials, methods: %w[POST], prefix: nil,
                key: :azure_git),
      Route.new(name: "cloud-credentials", callback: :cloud_credentials, methods: %w[POST], prefix: nil, key: :cloud),
      # Stored files on the filesystem storage, which Rails serves under
      # /store without a key: a presigned S3 URL is never rewritten
      # (ContainerAssetUrl), so only these reach the proxy. They carry no
      # session key, so the route needs only a session on the environment.
      Route.new(name: "assets", callback: :container_assets, methods: %w[GET HEAD], prefix: "store/", key: nil)
    ].index_by(&:name).freeze

    # The header that carries each credential endpoint's key, next to
    # `X-Session-Id` (the controllers of those endpoints read the same).
    KEY_HEADERS = {
      agent: "X-Agent-Key", git: "X-Git-Key", azure_git: "X-Azure-Git-Key", cloud: "X-Cloud-Key"
    }.freeze
    KEY_CHECKS = {
      agent: ->(session, key) { Agents::SessionKey.valid?(session, key) },
      git: ->(session, key) { GitCredentials::SessionKey.valid?(session, key) },
      azure_git: ->(session, key) { AzureDevops::GitSessionKey.valid?(session, key) },
      cloud: ->(session, key) { CloudAuth::SessionKey.valid?(session, key) }
    }.freeze

    module_function

    def route(name)
      ROUTES[name.to_s]
    end

    # The address a runner session calls a callback on: its proxy's route.
    # Nil for `:otel`: there is no OTLP route yet, so a runner session gets
    # no telemetry endpoint.
    def local_url(callback, session)
      return nil if callback.to_sym == :otel

      route = ROUTES.values.find { |candidate| candidate.callback == callback.to_sym }
      raise ArgumentError, "unknown callback #{callback.inspect}" if route.nil?

      "http://#{LOOPBACK}:#{port(session)}/#{route.name}"
    end

    # The sidecar's constant port, or with `network: host` the session's
    # port on the machine.
    def port(session)
      host_network?(session) ? host_port(session) : PORT
    end

    def host_port(session)
      HOST_PORT_BASE + (session.id % HOST_PORT_SPAN)
    end

    def host_network?(session)
      Runners::ConfigSchema.value(session.runner&.config || {}, "container.network") == "host"
    end

    # The session that holds the environment, when the forwarded request
    # carries that session's own key for the route (DESIGN.md §6.6, step 2).
    # Nil otherwise: the environment holds no session, the key is missing or
    # wrong, or it is another session's. The internal endpoint checks the key
    # again; this check is what ties it to the machine.
    def holder(route, environment, headers)
      session = environment.current_session
      return nil if session.nil?
      return session if route.key.nil?

      session if key_of?(route.key, session, headers)
    end

    def key_of?(kind, session, headers)
      if kind == :mcp
        key = headers["X-Session-Key"].to_s
        return false if key.blank? || key.start_with?(User::MCP_TOKEN_PREFIX)

        found = MCP::SessionKey.session_for(key) || TerminalSession.find_by(mcp_key: key)
        return found&.id == session.id
      end

      return false unless headers["X-Session-Id"].to_s == session.id.to_s

      key = headers[KEY_HEADERS.fetch(kind)].to_s
      key.present? && KEY_CHECKS.fetch(kind).call(session, key)
    end

    # The internal endpoint a route forwards to: the hosted callback address,
    # with the path below the route for a prefix route, and the query.
    def upstream_url(route, path, query)
      base = ContainerRuntime::CallbackUrls.hosted(route.callback).to_s
      base = "http://#{base}" unless base.match?(%r{\Ahttps?://})
      uri = URI.parse(base)
      uri.path = "#{uri.path.chomp('/')}/#{path}" if route.prefix
      uri.query = query.presence
      uri
    end
  end
end
