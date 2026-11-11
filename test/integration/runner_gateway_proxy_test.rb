# frozen_string_literal: true

require "test_helper"
require "socket"

# The callback proxy's gateway route, `ANY /runner/v1/proxy/:route/*`
# (docs/design/agent-runtimes/DESIGN.md §6.6; runner/protocol/PROTOCOL.md
# §5.8): the allow-list, the session-key check against the session that holds
# the environment, and the forward to the internal endpoint with the answer
# streamed back. The conformance fixtures (runner/protocol/fixtures/v1/proxy/)
# pin the refusals as the runner sees them; this test covers what the fixtures
# cannot: the request as the internal endpoint receives it, every credential
# route's key, and a streamed answer.
class RunnerGatewayProxyTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  REGISTRATION = { os: "linux", arch: "amd64", facts: {}, ephemeral: false }.freeze

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    @pair = registered_pair("build-01")
    @environment = RunnerEnvironment.sole
    @session = create(:runner_session, environment: @environment)
    @environment.update!(current_session: @session)
  end

  test "an MCP call of the session that holds the machine reaches the MCP server unchanged, plus the environment" do
    upstream = stub_request(:post, Settings.mcp.server_url)
               .to_return(status: 200, body: '{"jsonrpc":"2.0","id":1,"result":{}}',
                          headers: { "Content-Type" => "application/json", "Mcp-Session-Id" => "mcp-1" })

    post "/runner/v1/proxy/mcp", params: '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
                                 headers: proxy_headers("X-Session-Key" => @session.mcp_key, "Content-Type" => "application/json",
                                                        "Accept" => "application/json, text/event-stream",
                                                        "X-Aixle-Runner-Environment" => "999")

    assert_response :ok
    assert_equal '{"jsonrpc":"2.0","id":1,"result":{}}', response.body
    assert_equal "mcp-1", response.headers["Mcp-Session-Id"]
    assert_nil response.headers["X-Aixle-Runner-Refusal"]
    assert_requested(upstream)
    assert_requested(:post, Settings.mcp.server_url) do |request|
      request.body == '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' &&
        request.headers["X-Session-Key"] == @session.mcp_key &&
        request.headers["Content-Type"] == "application/json" &&
        request.headers["Accept"] == "application/json, text/event-stream" &&
        request.headers["X-Aixle-Runner-Environment"] == @environment.id.to_s &&
        request.headers["Authorization"].nil? &&
        request.headers["X-Aixle-Runner-Protocol"].nil? && request.headers["X-Aixle-Runner-Version"].nil?
    end
  end

  test "each credential route forwards to its endpoint with its own key of the session" do
    routes = {
      "agent-credentials" => [ Settings.agents.credential_sync_url, "X-Agent-Key", Agents::SessionKey ],
      "agent-credentials-refresh" => [ Settings.agents.credential_refresh_url, "X-Agent-Key", Agents::SessionKey ],
      "git-credentials" => [ Settings.git.credentials_url, "X-Git-Key", GitCredentials::SessionKey ],
      "azure-git-credentials" => [ Settings.azure_devops.git_credentials_url, "X-Azure-Git-Key", AzureDevops::GitSessionKey ],
      "cloud-credentials" => [ Settings.cloud.credentials_url, "X-Cloud-Key", CloudAuth::SessionKey ]
    }
    routes.each do |route, (url, header, key)|
      upstream = stub_request(:post, url).to_return(status: 200, body: "{}")
      good = key.generate(@session)

      post "/runner/v1/proxy/#{route}", params: "{}", headers: proxy_headers("X-Session-Id" => @session.id.to_s, header => good)
      assert_response :ok, route
      assert_requested upstream

      post "/runner/v1/proxy/#{route}", params: "{}", headers: proxy_headers("X-Session-Id" => @session.id.to_s, header => "#{good}x")
      assert_refused :forbidden, "session_not_on_environment", route

      other = create(:runner_session, environment: create(:runner_environment, runner: @runner))
      post "/runner/v1/proxy/#{route}", params: "{}",
                                        headers: proxy_headers("X-Session-Id" => other.id.to_s, header => key.generate(other))
      assert_refused :forbidden, "session_not_on_environment", route
      assert_requested upstream, times: 1
    end
  end

  test "stored files pass under store/ only, with a GET or a HEAD, and need only a session on the machine" do
    upstream = stub_request(:get, "http://#{Settings.container_asset_host}/store/ab/report%20one.pdf?v=1")
               .to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })

    get "/runner/v1/proxy/assets/store/ab/report%20one.pdf?v=1", headers: proxy_headers

    assert_response :ok
    assert_equal "%PDF", response.body
    assert_requested upstream

    post "/runner/v1/proxy/assets/store/ab/report.pdf", headers: proxy_headers
    assert_refused :not_found, "route_not_allowed"
    get "/runner/v1/proxy/assets/store/%2e%2e/secrets", headers: proxy_headers
    assert_refused :not_found, "route_not_allowed"
    get "/runner/v1/proxy/assets/store/a%5cb", headers: proxy_headers
    assert_refused :not_found, "route_not_allowed"
    get "/runner/v1/proxy/assets/public/index.html", headers: proxy_headers
    assert_refused :not_found, "route_not_allowed"

    # A path that does not decode strictly: octets that are not UTF-8, and
    # malformed triplets, which the test client cannot put in a URL, so they
    # go in PATH_INFO as a server passes them. Refused, not raised.
    %w[store/%FF store/a%C3 store/%C0%AF].each do |path|
      get "/runner/v1/proxy/assets/#{path}", headers: proxy_headers
      assert_refused :not_found, "route_not_allowed", path
    end
    %w[store/a% store/a%zz store/%G1/x].each do |path|
      get "/runner/v1/proxy/assets/store/x", headers: proxy_headers, env: { "PATH_INFO" => "/runner/v1/proxy/assets/#{path}" }
      assert_refused :not_found, "route_not_allowed", path
    end
    # Raw octets outside ASCII, valid UTF-8 or not: the path is the
    # percent-encoded form, so they are refused before they are decoded.
    [ "store/\xC3\xA9".b, "store/caf\xC3\xA9.pdf".b, "store/\xFF".b ].each do |path|
      get "/runner/v1/proxy/assets/store/x", headers: proxy_headers,
                                             env: { "PATH_INFO" => "/runner/v1/proxy/assets/".b + path }
      assert_refused :not_found, "route_not_allowed", path.inspect
    end

    @environment.update!(current_session: nil)
    get "/runner/v1/proxy/assets/store/ab/report%20one.pdf?v=1", headers: proxy_headers
    assert_refused :forbidden, "session_not_on_environment"
    assert_requested upstream, times: 1
  end

  test "a personal MCP token does not pass as a session key" do
    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers("X-Session-Key" => "#{User::MCP_TOKEN_PREFIX}personal")

    assert_refused :forbidden, "session_not_on_environment"
  end

  test "a session that no longer holds the machine is refused, even with its own key" do
    @environment.update!(current_session: nil)

    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers("X-Session-Key" => @session.mcp_key)

    assert_refused :forbidden, "session_not_on_environment"
  end

  test "an endpoint that does not answer is upstream_unavailable" do
    stub_request(:post, Settings.mcp.server_url).to_raise(Errno::ECONNREFUSED)

    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers("X-Session-Key" => @session.mcp_key)

    assert_refused :bad_gateway, "upstream_unavailable"
  end

  # This harness runs the request in-process and hands back the finished
  # response, so it cannot observe partial delivery: a gateway that buffered
  # both chunks until the upstream closed would pass too. What it checks is
  # that a chunked, event-stream answer reaches the runner whole and as it was
  # sent. Incremental streaming is covered by the Go relay's
  # TestTheProxyStreamsTheAnswerAsItComes (runner/internal/proxy), which holds
  # the second chunk back and reads the first.
  test "an answer the endpoint streams in chunks reaches the runner whole, as it was sent" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    seen = Queue.new
    thread = Thread.new do
      client = server.accept
      request = +""
      request << client.readpartial(4096) until request.include?("\r\n\r\n")
      seen << request
      client.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
      [ "event: message\ndata: one\n\n", "event: message\ndata: two\n\n" ].each do |chunk|
        client.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n")
        client.flush
        sleep 0.05
      end
      client.write("0\r\n\r\n")
      client.close
    end
    Settings.mcp.stubs(:server_url).returns("http://127.0.0.1:#{port}/action_mcp")

    get "/runner/v1/proxy/mcp", headers: proxy_headers("X-Session-Key" => @session.mcp_key, "Accept" => "text/event-stream")

    assert_response :ok
    assert_equal "text/event-stream", response.headers["Content-Type"]
    assert_equal "event: message\ndata: one\n\nevent: message\ndata: two\n\n", response.body
    assert_match %r{\AGET /action_mcp HTTP/1.1}, seen.pop
  ensure
    thread&.join(5)
    server&.close
  end

  test "headers that the Connection header nominates are not forwarded, in either direction" do
    upstream = stub_request(:post, Settings.mcp.server_url)
               .to_return(status: 200, body: "{}",
                          headers: { "Connection" => "X-Hop", "X-Hop" => "upstream-only", "X-Kept" => "kept" })

    post "/runner/v1/proxy/mcp", params: "{}",
                                 headers: proxy_headers("X-Session-Key" => @session.mcp_key, "Connection" => "keep-alive, X-Hop",
                                                        "X-Hop" => "runner-only", "X-Kept" => "kept")

    assert_response :ok
    assert_requested(upstream)
    assert_requested(:post, Settings.mcp.server_url) do |request|
      request.headers["X-Hop"].nil? && request.headers["X-Kept"] == "kept"
    end
    assert_nil response.headers["X-Hop"]
    assert_nil response.headers["Connection"]
    assert_equal "kept", response.headers["X-Kept"]
  end

  test "a runner that disconnects during the answer is logged, not raised" do
    stub_request(:post, Settings.mcp.server_url).to_raise(ActionController::Live::ClientDisconnected)
    Rails.logger.stubs(:info)
    Rails.logger.expects(:info).with(regexp_matches(/the runner disconnected during the answer/)).once

    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers("X-Session-Key" => @session.mcp_key)

    assert_nil response.headers["X-Aixle-Runner-Refusal"]
  end

  test "every refusal of the route carries the refusal header, the common ones included" do
    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers.merge("Authorization" => "Bearer aracc_unknown")
    assert_refused :unauthorized, "invalid_token"

    post "/runner/v1/proxy/mcp", params: "{}", headers: proxy_headers.merge("X-Aixle-Runner-Protocol" => "2")
    assert_refused :bad_request, "unsupported_protocol"
  end

  private

  def assert_refused(status, error, message = nil)
    assert_response status, message
    assert_equal error, response.parsed_body["error"], message
    assert_equal error, response.headers["X-Aixle-Runner-Refusal"], message
  end

  def proxy_headers(extra = {})
    { "Authorization" => "Bearer #{@pair['access_token']}", "X-Aixle-Runner-Protocol" => "1",
      "X-Aixle-Runner-Version" => "1.4.0" }.merge(extra)
  end

  def registered_pair(name)
    post "/runner/v1/register", params: REGISTRATION.merge(name: name),
                                headers: { "Authorization" => "Bearer #{Runners::Credentials.mint_registration!(@runner)}",
                                           "X-Aixle-Runner-Protocol" => "1", "X-Aixle-Runner-Version" => "1.4.0" },
                                as: :json
    assert_response :created
    response.parsed_body
  end
end
