# frozen_string_literal: true

module StubSupport
  # ===========================================================================
  # Session concurrency defaults
  #
  # The size of a project/user session queue is read live from the environment,
  # so a test that wants a small cap sets the same variable the deployment does.
  # Each parallel worker is its own process, and tests inside one run serially,
  # so mutating ENV here is confined to this test.
  # ===========================================================================

  def with_scope_defaults(project: 1, user: 1)
    previous = ENV.slice(*SessionAdmissionPolicy::SCOPE_DEFAULTS.values.pluck(:variable))
    ENV["SESSION_PROJECT_CONCURRENCY_DEFAULT"] = project.to_s
    ENV["SESSION_USER_CONCURRENCY_DEFAULT"] = user.to_s
    @_scope_defaults_restore = previous
  end

  def restore_scope_defaults
    return unless defined?(@_scope_defaults_restore) && @_scope_defaults_restore

    SessionAdmissionPolicy::SCOPE_DEFAULTS.each_value do |config|
      value = @_scope_defaults_restore[config[:variable]]
      value.nil? ? ENV.delete(config[:variable]) : ENV[config[:variable]] = value
    end
    @_scope_defaults_restore = nil
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
    Settings.stubs(:otel).returns(Hashie::Mash.new(endpoint: "http://otel:4318", metrics_endpoint: "http://otel:4318/v1/metrics"))
    Settings.stubs(:container_asset_host).returns(nil)
    Settings.stubs(:kubernetes).returns(Hashie::Mash.new(namespace: "test-ns", ready_timeout: 0.1, ready_interval: 0))
  end
end
