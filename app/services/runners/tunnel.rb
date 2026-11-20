# frozen_string_literal: true

module Runners
  # The ports of a runner session's interactive surfaces, which the tunnel
  # reaches (docs/design/agent-runtimes/runner-relay.md §3.3; runner/protocol/PROTOCOL.md
  # §6.2): `container.start` carries them as `tunnel.ports`, the relay learns
  # them from the `machine_session` signal and the holders call, and the
  # runner serves exactly these five for exactly that session.
  #
  #   Runners::Tunnel.ports(session)      # => {"tty" => 7681, "view" => 7682, "fs" => 4040, "upload" => 4041, "ide" => 8443}
  #   Runners::Tunnel.env_vars(session)   # => {"TTYD_PORT" => "7681", ...}, only with `network: host`
  #
  # - Bridge network: the image's own ports, in the session's own network namespace.
  # - `network: host`: the agent shares the machine's network namespace, so each
  #   session needs five ports of its own: `base + (session id mod 1000) * 8 + 0...4`
  #   (`Settings.runners.tunnel.host_port_base`, 30000 by default), derived the way
  #   Proxy.host_port derives the proxy's, so the platform chooses and the sides
  #   cannot disagree.
  module Tunnel
    # The surfaces, in the order of a session's five consecutive ports, with the
    # port the image serves each on and the environment variable the image reads it from.
    Surface = Data.define(:name, :image_port, :variable)

    SURFACES = [
      Surface.new(name: "tty", image_port: 7681, variable: "TTYD_PORT"),
      Surface.new(name: "view", image_port: 7682, variable: "VIEW_PORT"),
      Surface.new(name: "fs", image_port: 4040, variable: "WATCHER_PORT"),
      Surface.new(name: "upload", image_port: 4041, variable: "UPLOAD_PORT"),
      Surface.new(name: "ide", image_port: 8443, variable: "VSCODE_PORT")
    ].freeze

    # Sessions that get a block of ports of their own, and the ports in a block
    # (five used, eight reserved).
    SLOTS = 1000
    BLOCK = 8

    module_function

    def ports(session)
      if host_network?(session)
        first = host_base + ((session.id % SLOTS) * BLOCK)
        SURFACES.each_with_index.to_h { |surface, offset| [ surface.name, first + offset ] }
      else
        SURFACES.to_h { |surface| [ surface.name, surface.image_port ] }
      end
    end

    # The variables the image reads its ports from, for `container.start`'s `env`.
    # Only for a `network: host` session on a machine the platform has turned the
    # tunnel on for (TunnelTicket.enabled?, the check-in's `config.tunnel`): the
    # ports move where the session binds on the machine, so nothing moves for a
    # machine until then. Empty otherwise.
    def env_vars(session)
      return {} unless host_network?(session) && TunnelTicket.enabled?

      ports = ports(session)
      SURFACES.to_h { |surface| [ surface.variable, ports.fetch(surface.name).to_s ] }
    end

    def host_network?(session)
      Proxy.host_network?(session)
    end

    def host_base
      Integer(Settings.runners.tunnel.host_port_base)
    end

    # What is wrong with Settings.runners.tunnel: one message per broken rule,
    # each naming its variable. config/initializers/required_env.rb refuses to
    # boot on the first. Empty when the settings are usable.
    def settings_problems(settings = Settings.runners.tunnel, proxy = Settings.runners.proxy)
      base = Integer(settings.host_port_base, exception: false)
      return [ "RUNNERS_TUNNEL_HOST_PORT_BASE must be an integer, not #{settings.host_port_base.inspect}" ] if base.nil?

      range = base..(base + (SLOTS * BLOCK) - 1)
      [
        bounds_problem(base, range),
        proxy_overlap_problem(range, proxy),
        image_ports_problem(range)
      ].compact
    end

    def bounds_problem(base, range)
      return if base >= 1024 && range.end <= 65_535

      "RUNNERS_TUNNEL_HOST_PORT_BASE must be at least 1024 and leave room for #{SLOTS * BLOCK} ports " \
        "(at most 65535 as the last), not #{base}"
    end

    # The proxy's host ports (Proxy.host_port) are on the same network namespace.
    def proxy_overlap_problem(range, proxy)
      base = Integer(proxy.host_port_base, exception: false)
      span = Integer(proxy.host_port_span, exception: false)
      return if base.nil? || span.nil? || span < 1

      last = base + span - 1
      return unless range.begin <= last && base <= range.end

      "RUNNERS_TUNNEL_HOST_PORT_BASE..+#{SLOTS * BLOCK - 1} (#{range.begin}..#{range.end}) must not overlap the " \
        "proxy's host ports RUNNER_PROXY_HOST_PORT_BASE..+RUNNER_PROXY_HOST_PORT_SPAN - 1 (#{base}..#{last})"
    end

    def image_ports_problem(range)
      taken = Proxy::IMAGE_PORTS.select { |port| range.cover?(port) }
      return if taken.empty?

      "RUNNERS_TUNNEL_HOST_PORT_BASE..+#{SLOTS * BLOCK - 1} (#{range.begin}..#{range.end}) must not include the " \
        "agent image's own ports (#{Proxy::IMAGE_PORTS.join(', ')}), but it includes #{taken.sort.join(', ')}"
    end
    private_class_method :bounds_problem, :proxy_overlap_problem, :image_ports_problem
  end
end
