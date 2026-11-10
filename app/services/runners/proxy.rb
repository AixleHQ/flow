# frozen_string_literal: true

module Runners
  # The callback proxy (docs/design/agent-runtimes/DESIGN.md §6.6, §6.9.3;
  # runner/protocol/PROTOCOL.md §5.8). An agent on a runner cannot reach the
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

    # One allow-listed route: its path segment, the callback it stands for
    # (ContainerRuntime::CallbackUrls), the methods it takes, whether a path
    # below it passes (`prefix`, the first segment it must start with) and
    # the session key it is checked by.
    Route = Data.define(:name, :callback, :verbs, :prefix, :key) do
      # Whether a request of this method, with this path below the route (as
      # it was sent, percent-encoded), passes. A route without a prefix takes
      # no path below it, and no segment may lead out of the prefix: none is
      # empty, `.` or `..` once decoded, or holds a decoded `/` or `\`, as the
      # host runner's relay checks (runner/internal/proxy, `canonical`).
      def allows?(method, path)
        return false unless verbs.include?(method.to_s.upcase)

        path = path.to_s
        return path.empty? if prefix.nil?

        segments = path.split("/", -1).map { |segment| CGI.unescape(segment) }
        path.start_with?(prefix) && segments.none? { |segment| segment.empty? || %w[. ..].include?(segment) || segment.match?(%r{[/\\]}) }
      end
    end

    ROUTES = [
      Route.new(name: "mcp", callback: :mcp, verbs: %w[GET POST DELETE], prefix: nil, key: :mcp),
      Route.new(name: "agent-credentials", callback: :agent_credential_sync, verbs: %w[POST], prefix: nil, key: :agent),
      Route.new(name: "agent-credentials-refresh", callback: :agent_credential_refresh, verbs: %w[POST], prefix: nil,
                key: :agent),
      Route.new(name: "git-credentials", callback: :git_credentials, verbs: %w[POST], prefix: nil, key: :git),
      Route.new(name: "azure-git-credentials", callback: :azure_git_credentials, verbs: %w[POST], prefix: nil,
                key: :azure_git),
      Route.new(name: "cloud-credentials", callback: :cloud_credentials, verbs: %w[POST], prefix: nil, key: :cloud),
      # Stored files on the filesystem storage, which Rails serves under
      # /store without a key: a presigned S3 URL is never rewritten
      # (ContainerAssetUrl), so only these reach the proxy. They carry no
      # session key, so the route needs only a session on the environment,
      # and it passes any path under /store: under the filesystem storage
      # every company's stored files are there. That is safe only because
      # Shrine uses the filesystem storage in development alone
      # (config/initializers/shrine.rb). A deployment that serves stored files
      # from the filesystem (self-hosted, say) must give this route a key
      # check first, or a runner session could read another company's files.
      Route.new(name: "assets", callback: :container_assets, verbs: %w[GET HEAD], prefix: "store/", key: nil)
    ].index_by(&:name).freeze

    # The module that checks each credential endpoint's key, and names the
    # header it travels in next to `X-Session-Id`: the controllers of those
    # endpoints read the same.
    SESSION_KEYS = {
      agent: Agents::SessionKey, git: GitCredentials::SessionKey,
      azure_git: AzureDevops::GitSessionKey, cloud: CloudAuth::SessionKey
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

    # The session's port of its proxy, which `container.start` sends as
    # `proxy_port`: the sidecar's (`Settings.runners.proxy.port`), or with
    # `network: host` the session's port on the machine.
    def port(session)
      host_network?(session) ? host_port(session) : sidecar_port
    end

    # The sidecar's port, outside the agent image's own ports (IMAGE_PORTS).
    def sidecar_port
      Integer(Settings.runners.proxy.port)
    end

    # With `network: host` the agent shares the machine's network namespace,
    # so the host runner listens on the machine's 127.0.0.1, and every
    # session needs a port of its own there: one in
    # host_port_base...host_port_base + host_port_span, from the session's
    # id. The port has to be known when the strategy builds the container's
    # environment, before the session takes a machine, so it cannot come
    # from the machine.
    def host_port(session)
      settings = Settings.runners.proxy
      Integer(settings.host_port_base) + (session.id % Integer(settings.host_port_span))
    end

    # The agent image's own ports, which the sidecar shares a network
    # namespace with.
    IMAGE_PORTS = [ 7681, 7682, 4040, 4041, 8443, 8888 ].freeze

    # What is wrong with Settings.runners.proxy: one message per broken rule,
    # each naming its variable. config/initializers/required_env.rb refuses
    # to boot on the first. Empty when the settings are usable.
    def settings_problems(settings = Settings.runners.proxy)
      port, base, span = [ settings.port, settings.host_port_base, settings.host_port_span ].map do |value|
        Integer(value, exception: false)
      end
      [
        port_problem(port, settings.port),
        minimum_problem("RUNNER_PROXY_HOST_PORT_BASE", base, settings.host_port_base, 1024),
        minimum_problem("RUNNER_PROXY_HOST_PORT_SPAN", span, settings.host_port_span, 1),
        host_range_problem(base, span)
      ].compact
    end

    def minimum_problem(variable, value, raw, minimum)
      "#{variable} must be at least #{minimum}, not #{raw.inspect}" unless value && value >= minimum
    end

    def port_problem(port, raw)
      return if port && (1024..65_535).cover?(port) && IMAGE_PORTS.exclude?(port)

      "RUNNER_PROXY_PORT must be in 1024..65535 and outside the agent image's own ports " \
        "(#{IMAGE_PORTS.join(', ')}), not #{raw.inspect}"
    end

    def host_range_problem(base, span)
      return if base.nil? || span.nil? || span < 1 || base + span - 1 <= 65_535

      "RUNNER_PROXY_HOST_PORT_BASE + RUNNER_PROXY_HOST_PORT_SPAN - 1 must be at most 65535, not #{base + span - 1}"
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
      return MCP::SessionKey.lookup(headers[MCP::SessionKey::HEADER])&.id == session.id if kind == :mcp
      return false unless headers["X-Session-Id"].to_s == session.id.to_s

      key_module = SESSION_KEYS.fetch(kind)
      key = headers[key_module::HEADER].to_s
      key.present? && key_module.valid?(session, key)
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
