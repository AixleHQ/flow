# frozen_string_literal: true

module StubSupport
  # ===========================================================================
  # Session concurrency defaults
  #
  # The only deployment input left is the per-project default, read from Settings
  # which loads it from the environment at boot — so a test that wants a small
  # default replaces the settings block rather than mutating the process
  # environment. Capacity itself is a SessionConcurrencyLimit row.
  # ===========================================================================

  def with_scope_defaults(project: 1)
    Settings.stubs(:session_admission).returns(
      Hashie::Mash.new(project_default: project)
    )
  end

  # Admission on with nothing above the project tier: no company has a limit, so
  # a project's pool cap is the only bound. This is what most tests want — they
  # care that the queue holds at N, not which tier produced N.
  def with_admission(project: 4)
    with_scope_defaults(project: project)
    SessionAdmissionPolicy.sync!
  end

  # Admission on, with a company that has bought `limit` concurrent sessions.
  # Capacity is a database row now, not a deployment variable, so this writes one
  # — `sync!` only performs the cutover. `project:` defaults to the built-in
  # fallback so a test that only cares about the company keeps the pool caps it
  # would have had otherwise.
  def with_company_limit(company, limit, project: 4)
    with_scope_defaults(project: project)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: limit)
    SessionAdmissionPolicy.sync!
  end

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
  # Common Settings Stubs
  # ===========================================================================

  def stub_container_settings
    Settings.stubs(:docker).returns(Hashie::Mash.new(network: "bridge"))
    Settings.stubs(:traefik).returns(Hashie::Mash.new(ws_base: "wss://test.example.com", internal_url: "http://traefik"))
    Settings.stubs(:mcp).returns(Hashie::Mash.new(server_url: "http://mcp.test/mcp"))
    Settings.stubs(:otel).returns(Hashie::Mash.new(endpoint: "http://otel:4318"))
    Settings.stubs(:container_asset_host).returns(nil)
    Settings.stubs(:kubernetes).returns(Hashie::Mash.new(namespace: "test-ns", ready_timeout: 0.1, ready_interval: 0))
  end
end
