# frozen_string_literal: true

require "test_helper"

# Runners::Tunnel (docs/design/agent-runtimes/runner-relay.md §3.3; runner/protocol/PROTOCOL.md
# §6.2): the five ports of a runner session's interactive surfaces.
class Runners::TunnelTest < ActiveSupport::TestCase
  BRIDGE_PORTS = { "tty" => 7681, "view" => 7682, "fs" => 4040, "upload" => 4041, "ide" => 8443 }.freeze

  setup do
    @runner = create(:runner, :manual)
    @environment = create(:runner_environment, runner: @runner)
    @session = create(:runner_session, environment: @environment)
  end

  test "on the bridge network a session's ports are the image's own" do
    assert_equal BRIDGE_PORTS, Runners::Tunnel.ports(@session)
  end

  test "with network: host a session has five consecutive ports from its id, like the proxy's port" do
    host_network!
    first = 30_000 + ((@session.id % 1000) * 8)

    ports = Runners::Tunnel.ports(@session.reload)

    assert_equal %w[tty view fs upload ide], ports.keys
    assert_equal (first..(first + 4)).to_a, ports.values
  end

  test "the base is a setting" do
    host_network!
    Settings.runners.stubs(:tunnel).returns(Hashie::Mash.new(host_port_base: 40_000))

    assert_equal 40_000 + ((@session.id % 1000) * 8), Runners::Tunnel.ports(@session.reload)["tty"]
  end

  test "the image's port variables are set from the host ports only with network: host and the tunnel on" do
    host_network!
    session = @session.reload
    ports = Runners::Tunnel.ports(session)

    assert_empty Runners::Tunnel.env_vars(session), "the tunnel is off"

    tunnel_on do
      assert_equal({ "TTYD_PORT" => ports["tty"].to_s, "VIEW_PORT" => ports["view"].to_s, "WATCHER_PORT" => ports["fs"].to_s,
                     "UPLOAD_PORT" => ports["upload"].to_s, "VSCODE_PORT" => ports["ide"].to_s },
                   Runners::Tunnel.env_vars(session))
    end
  end

  test "on the bridge network no port variable is set, the tunnel on or off" do
    assert_empty Runners::Tunnel.env_vars(@session)
    tunnel_on { assert_empty Runners::Tunnel.env_vars(@session) }
  end

  test "the default settings are usable" do
    assert_empty Runners::Tunnel.settings_problems
  end

  test "a base below 1024, or a range past 65535, is refused" do
    assert_match(/at least 1024/, problem(host_port_base: 1000))
    assert_match(/at least 1024/, problem(host_port_base: 60_000))
    assert_empty Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 65_535 - 7999))
  end

  test "a base that is not a number is refused" do
    assert_match(/must be an integer/, problem(host_port_base: "abc"))
  end

  test "a range that overlaps the proxy's host ports is refused, on either side" do
    proxy = Hashie::Mash.new(port: 7690, host_port_base: 20_000, host_port_span: 10_000)

    assert_empty Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 30_000), proxy)
    assert_match(/proxy's host ports/, Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 29_999), proxy).first)
    assert_match(/proxy's host ports/, Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 12_100), proxy).first)
    assert_empty Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 12_000), proxy.merge(host_port_base: 20_000, host_port_span: 100))
  end

  test "a range that includes one of the image's own ports is refused" do
    problems = Runners::Tunnel.settings_problems(Hashie::Mash.new(host_port_base: 4000),
                                                 Hashie::Mash.new(port: 7690, host_port_base: 50_000, host_port_span: 100))

    assert_equal 1, problems.size
    assert_match(/image's own ports.*includes 4040, 4041, 7681, 7682, 8443, 8888/, problems.first)
  end

  private

  def host_network!
    @runner.update!(config: { "container" => { "network" => "host" } })
  end

  def tunnel_on
    Settings.runners.relay.stubs(:ticket_key).returns("a-ticket-key-of-32-characters-xx")
    Runners::TunnelTicket.stubs(:mode).returns("session")
    yield
  end

  def problem(**settings)
    Runners::Tunnel.settings_problems(Hashie::Mash.new(settings), Hashie::Mash.new(port: 7690, host_port_base: 20_000, host_port_span: 100)).first
  end
end
