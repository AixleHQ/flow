# frozen_string_literal: true

require "test_helper"

# Runners::Proxy (DESIGN.md §6.6, PROTOCOL.md §5.8): the address a runner
# session calls back on, the allow-list, the session-key check and the
# internal endpoint a route forwards to.
class Runners::ProxyTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @environment = create(:runner_environment, runner: @runner)
    @session = create(:runner_session, environment: @environment)
    @environment.update!(current_session: @session)
  end

  test "a runner session calls every callback on its sidecar's constant port, and gets no OTLP endpoint" do
    expected = {
      mcp: "http://127.0.0.1:7690/mcp",
      agent_credential_sync: "http://127.0.0.1:7690/agent-credentials",
      agent_credential_refresh: "http://127.0.0.1:7690/agent-credentials-refresh",
      git_credentials: "http://127.0.0.1:7690/git-credentials",
      azure_git_credentials: "http://127.0.0.1:7690/azure-git-credentials",
      cloud_credentials: "http://127.0.0.1:7690/cloud-credentials",
      container_assets: "http://127.0.0.1:7690/assets",
      otel: nil
    }

    assert_equal expected, ContainerRuntime::RunnerRuntime.new.callback_urls(@session)
  end

  test "with network: host the session calls its own port on the machine" do
    @runner.update!(config: { "container" => { "network" => "host" } })
    port = 20_000 + (@session.id % 10_000)

    assert_equal "http://127.0.0.1:#{port}/mcp", Runners::Proxy.local_url(:mcp, @session.reload)
    assert_operator port, :<, 65_536
  end

  test "the proxy's ports come from Settings, and container.start sends the session's" do
    Settings.runners.stubs(:proxy).returns(Hashie::Mash.new(port: 7800, host_port_base: 30_000, host_port_span: 100))

    assert_equal "http://127.0.0.1:7800/mcp", Runners::Proxy.local_url(:mcp, @session)
    assert_equal 7800, Runners::Proxy.port(@session)

    @runner.update!(config: { "container" => { "network" => "host" } })
    session = @session.reload
    assert_equal 30_000 + (session.id % 100), Runners::Proxy.port(session)
    assert_equal "http://127.0.0.1:#{30_000 + (session.id % 100)}/git-credentials",
                 Runners::Proxy.local_url(:git_credentials, session)
  end

  test "every callback but OTLP has a route, and every route a callback" do
    callbacks = ContainerRuntime::CallbackUrls::NAMES - [ :otel ]

    assert_equal callbacks.sort, Runners::Proxy::ROUTES.values.map(&:callback).sort
    assert_raises(ArgumentError) { Runners::Proxy.local_url(:nope, @session) }
  end

  test "a route passes only its methods, and only the paths below it that it takes" do
    mcp = Runners::Proxy.route("mcp")
    assets = Runners::Proxy.route("assets")

    assert mcp.allows?("POST", "")
    assert mcp.allows?("get", "")
    assert_not mcp.allows?("PUT", "")
    assert_not mcp.allows?("POST", "sessions")
    assert assets.allows?("GET", "store/ab/report%20one.pdf")
    assert assets.allows?("HEAD", "store/x")
    assert_not assets.allows?("POST", "store/x")
    assert_not assets.allows?("GET", "cache/x")
    assert_not assets.allows?("GET", "store/../x")
    assert_not assets.allows?("GET", "store/%2E%2E/x")
    assert_not assets.allows?("GET", "store/a%2Fb")
    assert_not assets.allows?("GET", "store/a%5cb")
    assert_not assets.allows?("GET", "store/a%5Cb")
    assert_not assets.allows?("GET", "store//x")
    assert_nil Runners::Proxy.route("otlp")
  end

  test "a path segment that does not decode strictly is refused, without raising" do
    assets = Runners::Proxy.route("assets")

    assert assets.allows?("GET", "store/a+b%C3%A9.pdf")
    # Malformed triplets: a `%` with no, one, or non-hex digits after it.
    %w[store/a% store/a%2 store/a%zz store/%G1/x store/a%%41].each do |path|
      assert_not assets.allows?("GET", path), path
    end
    # Octets that are not UTF-8: escaped, a truncated sequence, and raw.
    [ "store/%FF", "store/a%C3", "store/%C0%AF", "store/\xFF".b ].each do |path|
      assert_not assets.allows?("GET", path), path.inspect
    end
  end

  test "decode_segment decodes strictly" do
    assert_equal "a b+c", Runners::Proxy.decode_segment("a%20b+c")
    assert_equal "é", Runners::Proxy.decode_segment("%c3%a9")
    assert_nil Runners::Proxy.decode_segment("%")
    assert_nil Runners::Proxy.decode_segment("%4")
    assert_nil Runners::Proxy.decode_segment("%FF")
  end

  test "the MCP route takes the key of the session that holds the machine, and no other" do
    mcp = Runners::Proxy.route("mcp")
    other = create(:runner_session, environment: create(:runner_environment, runner: @runner))

    assert_equal @session, Runners::Proxy.holder(mcp, @environment, { "X-Session-Key" => @session.mcp_key })
    assert_nil Runners::Proxy.holder(mcp, @environment, { "X-Session-Key" => other.mcp_key })
    assert_nil Runners::Proxy.holder(mcp, @environment, { "X-Session-Key" => "#{@session.id}.forged" })
    assert_nil Runners::Proxy.holder(mcp, @environment, {})

    @environment.update!(current_session: nil)
    assert_nil Runners::Proxy.holder(mcp, @environment.reload, { "X-Session-Key" => @session.mcp_key })
  end

  test "a credential route takes the session's id and its own key, not another route's" do
    git = Runners::Proxy.route("git-credentials")
    key = GitCredentials::SessionKey.generate(@session)

    assert_equal @session, Runners::Proxy.holder(git, @environment, { "X-Session-Id" => @session.id.to_s, "X-Git-Key" => key })
    assert_nil Runners::Proxy.holder(git, @environment, { "X-Session-Id" => @session.id.to_s, "X-Git-Key" => "#{key}0" })
    assert_nil Runners::Proxy.holder(git, @environment, { "X-Session-Id" => (@session.id + 1).to_s, "X-Git-Key" => key })
    assert_nil Runners::Proxy.holder(git, @environment, { "X-Session-Id" => @session.id.to_s,
                                                          "X-Git-Key" => Agents::SessionKey.generate(@session) })
  end

  test "stored files need only a session on the machine" do
    assets = Runners::Proxy.route("assets")

    assert_equal @session, Runners::Proxy.holder(assets, @environment, {})
    @environment.update!(current_session: nil)
    assert_nil Runners::Proxy.holder(assets, @environment.reload, {})
  end

  test "a route forwards to the hosted address of its callback" do
    assert_equal Settings.mcp.server_url, Runners::Proxy.upstream_url(Runners::Proxy.route("mcp"), "", nil).to_s
    assert_equal "#{Settings.git.credentials_url}?a=1",
                 Runners::Proxy.upstream_url(Runners::Proxy.route("git-credentials"), "", "a=1").to_s
    assert_equal "http://#{Settings.container_asset_host}/store/a%20b.pdf",
                 Runners::Proxy.upstream_url(Runners::Proxy.route("assets"), "store/a%20b.pdf", "").to_s
  end
end
