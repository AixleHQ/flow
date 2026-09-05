# frozen_string_literal: true

module StubSupport
  # ===========================================================================
  # Container Runtime
  #
  # Injects the canonical ContainerRuntime::FakeRuntime (a real BaseRuntime with
  # an in-memory virtual filesystem — see test/support/fakes/fake_runtime.rb)
  # through the existing `ContainerRuntime.build` seam. No vendor stubbing, no
  # any_instance/define_method monkeypatching, no teardown bookkeeping — the fake
  # replaces the whole runtime, so callers (strategies, ContainerService) get it
  # uniformly regardless of the configured runtime name.
  # ===========================================================================

  def stub_container_runtime(_runtime_name = nil, agent_type: "claude_code")
    stub_runtime_timeouts
    @_fake_runtime = ContainerRuntime::FakeRuntime.new(agent_type: agent_type)
    ContainerRuntime.stubs(:build).returns(@_fake_runtime)
    @_fake_runtime
  end

  # The current fake installs no monkeypatch, so there is nothing to undo beyond
  # restoring the timeout constants. Kept as a named teardown hook for callers.
  def cleanup_runtime_overrides
    restore_runtime_timeouts
  end

  # ===========================================================================
  # Timeouts — shrink the strategy/runtime waiting-loop constants so tests don't
  # sleep. Restored in teardown via cleanup_runtime_overrides.
  # ===========================================================================

  ORIGINAL_TIMEOUTS = {
    [ ContainerRuntime::DockerRuntime,          :HEALTH_CHECK_TIMEOUT ]  => 30,
    [ ContainerRuntime::DockerRuntime,          :PORT_READY_TIMEOUT ]    => 30,
    [ ContainerRuntime::KubernetesRuntime,      :READY_TIMEOUT ]         => 30,
    [ ContainerStrategies::AgentSessionStrategy, :POLL_INTERVAL ]        => 5,
    [ ContainerStrategies::AgentSessionStrategy, :POLL_TIMEOUT ]         => 82_800
  }.freeze

  def stub_runtime_timeouts
    set_const(ContainerRuntime::DockerRuntime,          :HEALTH_CHECK_TIMEOUT,  0.1)
    set_const(ContainerRuntime::DockerRuntime,          :PORT_READY_TIMEOUT,    0.1)
    set_const(ContainerRuntime::KubernetesRuntime,      :READY_TIMEOUT,         0.1)
    set_const(ContainerStrategies::AgentSessionStrategy, :POLL_INTERVAL,        0)
    set_const(ContainerStrategies::AgentSessionStrategy, :POLL_TIMEOUT,         0.1)
  end

  def restore_runtime_timeouts
    ORIGINAL_TIMEOUTS.each { |(klass, name), value| set_const(klass, name, value) }
  end

  def set_const(klass, name, value)
    klass.send(:remove_const, name) if klass.const_defined?(name)
    klass.const_set(name, value)
  end

  # ===========================================================================
  # Traefik HTTP Stubs (WebMock)
  # ===========================================================================

  def stub_traefik_http
    stub_request(:get, %r{http://traefik}).to_return(status: 200)
    stub_request(:head, %r{https://traefik}).to_return(status: 200)
    stub_request(:any, %r{https://traefik\..*\.svc\.cluster\.local}).to_return(status: 200)
  end

  # ===========================================================================
  # Cursor Dashboard API (WebMock)
  #
  # Cursor is the one agent whose usage is not pushed to us during the run: it is
  # pulled at cleanup, by asking the dashboard which billing events fall inside
  # the session's AgentService windows. The fake runtime hands back a MITM log
  # holding a completed run and an auth.json holding an access token, so every
  # cursor_cli agent_session cleanup reaches that call for real — unstubbed, it
  # is a WebMock::NetConnectNotAllowedError, which descends from Exception and so
  # slips past the `rescue StandardError` around usage collection.
  #
  # The reply carries one event stamped just inside the queried window. The
  # window comes from MITM fixture timestamps, so the stub reads it back off the
  # request rather than guessing at wall-clock.
  # ===========================================================================

  CURSOR_USAGE_EVENTS_URL =
    "#{Agents::CursorCliAdapter::CURSOR_API_BASE}#{Agents::CursorCliAdapter::FILTERED_USAGE_ENDPOINT}"

  CURSOR_USAGE_EVENT = {
    "model" => "claude-4.5-sonnet",
    "kindLabel" => "Included in Business",
    "tokenUsage" => {
      "inputTokens" => 1_200,
      "outputTokens" => 340,
      "cacheWriteTokens" => 0,
      "cacheReadTokens" => 900,
      "totalCents" => 2.5
    }
  }.freeze

  def stub_cursor_usage_api(events: nil)
    stub_request(:post, CURSOR_USAGE_EVENTS_URL).to_return do |request|
      window_start_ms = JSON.parse(request.body)["startDate"].to_i
      display = events || [ CURSOR_USAGE_EVENT.merge("timestamp" => (window_start_ms + 1).to_s) ]

      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { "usageEventsDisplay" => display }.to_json
      }
    end
  end

  # ===========================================================================
  # Common Settings Stubs
  # ===========================================================================

  def stub_container_settings
    Settings.stubs(:docker).returns(Hashie::Mash.new(network: "bridge"))
    Settings.stubs(:traefik).returns(Hashie::Mash.new(ws_base: "wss://test.example.com", internal_url: "http://traefik"))
    Settings.stubs(:mcp).returns(Hashie::Mash.new(server_url: "http://mcp.test/mcp"))
    Settings.stubs(:otel).returns(Hashie::Mash.new(endpoint: "http://otel:4318", metrics_endpoint: "http://otel:4318/v1/metrics"))
    Settings.stubs(:container_asset_host).returns(nil)
    Settings.stubs(:kubernetes).returns(Hashie::Mash.new(namespace: "test-ns", ready_timeout: 0.1, ready_interval: 0))
  end
end
