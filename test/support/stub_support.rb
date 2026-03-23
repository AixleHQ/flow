# frozen_string_literal: true

module StubSupport
  # ===========================================================================
  # Container Runtime Stubs
  # ===========================================================================

  def stub_container_runtime(runtime_name, agent_type: "claude_code")
    stub_runtime_timeouts
    @_container_fs = container_filesystem(agent_type)

    case runtime_name.to_s
    when "kubernetes", "k8s"
      stub_kubernetes_runtime(@_container_fs)
    else
      stub_docker_runtime(@_container_fs)
    end
  end

  # ---------------------------------------------------------------------------
  # Docker: Mocha mocks + define_method on runtime for command routing
  # ---------------------------------------------------------------------------

  def stub_docker_runtime(fs)
    Docker::Image.stubs(:get).returns(Object.new)
    Docker::Image.stubs(:create).yields("{}")

    container = build_fake_docker_container(fs)
    Docker::Container.stubs(:create).returns(container)
    Docker::Container.stubs(:get).returns(container)
  end

  def build_fake_docker_container(fs)
    captured_fs = fs
    c = Object.new

    c.define_singleton_method(:id) { "abcdef1234567890abcdef" }
    c.define_singleton_method(:is_a?) { |klass| klass == Docker::Container || super(klass) }
    c.define_singleton_method(:start) { |*| self }
    c.define_singleton_method(:stop) { |*| self }
    c.define_singleton_method(:remove) { |*| true }
    c.define_singleton_method(:refresh!) { |*| self }
    c.define_singleton_method(:json) { { "State" => { "Running" => true, "Status" => "running" } } }
    c.define_singleton_method(:archive) do |path|
      content = captured_fs[path]
      content.nil? ? "" : StubSupport.build_tar_for_path(path, content)
    end
    c.define_singleton_method(:archive_in) { |*| true }
    c.define_singleton_method(:archive_out) do |path, &block|
      content = captured_fs[path]
      if content
        block&.call(StubSupport.build_tar_for_path(path, content))
      else
        block&.call("")
      end
    end
    c.define_singleton_method(:read_file) { |path| captured_fs[path] }
    c.define_singleton_method(:store_file) { |path, content| captured_fs[path] = content }
    c.define_singleton_method(:logs) { |*, **| "" }
    c.define_singleton_method(:wait) { |*| { "StatusCode" => 0 } }
    c.define_singleton_method(:kill) { |*| true }

    c.define_singleton_method(:exec) do |cmd, *_opts|
      StubSupport.route_exec_docker(cmd, captured_fs)
    end

    c
  end

  # ---------------------------------------------------------------------------
  # Kubernetes: Mocha mocks + define_method for exec and traefik
  # ---------------------------------------------------------------------------

  def stub_kubernetes_runtime(fs)
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:core_client).returns(stub_k8s_core_client)
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:traefik_client).returns(stub_k8s_traefik_client)
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:networking_client).returns(stub_k8s_networking_client)
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:in_cluster?).returns(false)
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:kube_endpoint).returns("https://localhost:6443")
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:kube_ssl_options).returns({})
    ContainerRuntime::KubernetesRuntime.any_instance.stubs(:kube_auth_options).returns({})

    captured_fs = fs
    ContainerRuntime::KubernetesRuntime.define_method(:exec_via_websocket) do |_handle, cmd, opts = {}|
      StubSupport.route_exec_k8s(cmd, captured_fs)
    end
    ContainerRuntime::KubernetesRuntime.define_method(:wait_for_traefik_route) { |_| true }

    @_k8s_original_copy_from = ContainerRuntime::KubernetesRuntime.instance_method(:copy_from)
    ContainerRuntime::KubernetesRuntime.define_method(:copy_from) do |_id, path|
      captured_fs[path]
    end

    @_k8s_original_read_file = ContainerRuntime::KubernetesRuntime.instance_method(:read_file)
    ContainerRuntime::KubernetesRuntime.define_method(:read_file) do |_id, path|
      captured_fs[path]
    end
  end

  def stub_k8s_core_client
    ready_pod = Kubeclient::Resource.new(
      status: { phase: "Running", conditions: [ { type: "Ready", status: "True" } ] }
    )
    core = mock("kubeclient_core")
    core.stubs(:get_namespace).returns(true)
    core.stubs(:create_namespace).returns(true)
    core.stubs(:create_pod).returns(true)
    core.stubs(:get_pod).returns(ready_pod)
    core.stubs(:delete_pod).returns(true)
    core.stubs(:create_service).returns(true)
    core.stubs(:get_service).returns(true)
    core.stubs(:delete_service).returns(true)
    core.stubs(:get_resource_quota).raises(Kubeclient::ResourceNotFoundError.new(404, "Not Found", nil))
    core.stubs(:create_resource_quota).returns(true)
    core.stubs(:update_resource_quota).returns(true)
    core
  end

  def stub_k8s_traefik_client
    traefik = mock("kubeclient_traefik")
    traefik.stubs(:discovered).returns(true)
    traefik.stubs(:discover).returns(true)
    traefik.stubs(:create_entity).returns(true)
    traefik.stubs(:get_entity).returns(true)
    traefik.stubs(:delete_entity).returns(true)
    traefik
  end

  def stub_k8s_networking_client
    networking = mock("kubeclient_networking")
    networking.stubs(:discovered).returns(true)
    networking.stubs(:discover).returns(true)
    networking.stubs(:create_entity).returns(true)
    networking.stubs(:get_entity).returns(true)
    networking
  end

  # ===========================================================================
  # Runtime method cleanup (call in teardown)
  # ===========================================================================

  RUNTIME_METHOD_OVERRIDES = {
    ContainerRuntime::KubernetesRuntime => [ :exec_via_websocket, :wait_for_traefik_route ]
  }.freeze

  def cleanup_runtime_overrides
    RUNTIME_METHOD_OVERRIDES.each do |klass, methods|
      methods.each do |m|
        klass.send(:remove_method, m)
      rescue NameError
        nil
      end
    end
    if @_k8s_original_copy_from
      ContainerRuntime::KubernetesRuntime.define_method(:copy_from, @_k8s_original_copy_from)
      @_k8s_original_copy_from = nil
    end
    if @_k8s_original_read_file
      ContainerRuntime::KubernetesRuntime.define_method(:read_file, @_k8s_original_read_file)
      @_k8s_original_read_file = nil
    end
    restore_runtime_timeouts
  end

  # ===========================================================================
  # Exec routing — maps commands to virtual filesystem
  # ===========================================================================

  def self.build_tar_for_path(path, content)
    normalized = path.to_s.sub(%r{\A/}, "")
    io = StringIO.new("".b)
    Gem::Package::TarWriter.new(io) do |tar|
      data = content.respond_to?(:b) ? content.b : content.to_s.b
      tar.add_file_simple(normalized, 0o644, data.bytesize) { |entry_io| entry_io.write(data) }
    end
    io.string
  end

  def self.route_exec_docker(cmd, fs)
    stdout = resolve_command(cmd, fs)
    [ [ stdout ], [ "" ], 0 ]
  end

  def self.route_exec_k8s(cmd, fs)
    stdout = resolve_command(cmd, fs)
    [ stdout, "", 0 ]
  end

  def self.resolve_command(cmd, fs)
    cmd_str = cmd.is_a?(Array) ? cmd.join(" ") : cmd.to_s

    return "open\n" if cmd_str.include?("echo 'open'")
    return "0\n" if cmd_str.include?(".agent_done")

    if cmd_str.include?("find") && cmd_str.include?("/workspace/outputs")
      return fs.keys.select { |k| k.start_with?("/workspace/outputs/") }.join("\n")
    end

    if (m = cmd_str.match(/cat\s+(\S+)/))
      return fs[m[1]] || ""
    end

    ""
  end

  # ===========================================================================
  # Timeouts
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
  # Per-agent virtual filesystem with realistic fixture data
  # ===========================================================================

  def container_filesystem(agent_type)
    auth = AUTH_CONFIGS.fetch(agent_type)
    log = MITM_LOGS.fetch(agent_type, "")

    fs = {}
    fs[auth[:path]] = auth[:content]
    fs["/var/log/mitm/http.log"] = log if log.present?
    fs["/tmp/terminal_output.log"] = terminal_output_fixture(agent_type)
    fs["/workspace/outputs/result.md"] = "# Result\n\nGenerated output.\n"
    fs
  end

  def terminal_output_fixture(agent_type)
    case agent_type
    when "claude_code"
      <<~LOG
        ╭─ Claude Code ─────────────────────────────────────────╮
        │                  Welcome back Test User!               │
        ╰───────────────────────────────────────────────────────╯

        > Create two test files with sample content

        I'll create two test files for you.

        ✓ Created file1.txt
        ✓ Created file2.txt

        Total cost: $0.03
        Duration: 8.2s
      LOG
    when "cursor_cli"
      <<~LOG

        Cursor Agent v2026.02.13-41ac335
        /workspace
        (cwd is not a git repository, cursor rules and ignore
        files don't apply)


        Create two test files with sample content


        Creating two test files in /workspace/outputs/.

        ✓ Wrote output/file1.txt (24 bytes)
        ✓ Wrote output/file2.txt (36 bytes)
      LOG
    when "codex"
      <<~LOG

        ╭───────────────────────────────────────╮
        │ >_ OpenAI Codex (v0.104.0)            │
        │                                       │
        │ model:     codex-mini-latest           │
        │ directory: /workspace                  │
        ╰───────────────────────────────────────╯

        > Create two test files with sample content

        Created file1.txt and file2.txt with sample content.
      LOG
    when "gemini_cli"
      <<~LOG
        Gemini CLI v0.1.0
        Model: gemini-2.5-pro

        > Create two test files with sample content

        Done. I created:
        - file1.txt
        - file2.txt
      LOG
    else
      "$ agent running\nTask completed.\n"
    end
  end

  AUTH_CONFIGS = {
    "claude_code" => {
      path: "/home/claude/.claude.json",
      content: {
        "oauthAccount" => {
          "accountUuid" => "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "emailAddress" => "test@example.com",
          "organizationUuid" => "org-uuid-1234-5678",
          "hasExtraUsageEnabled" => false,
          "displayName" => "Test User",
          "organizationRole" => "admin",
          "workspaceRole" => "workspace_developer",
          "organizationName" => "Test Org"
        },
        "primaryApiKey" => "sk-ant-api03-test-key-placeholder",
        "customApiKeyResponses" => { "approved" => [ "HfZnizK6U3g-test" ], "rejected" => [] },
        "userID" => "0ea9651c48666ae1test"
      }.to_json
    },
    "cursor_cli" => {
      path: "/home/cursor/.config/cursor/auth.json",
      content: {
        "accessToken" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdXRoMHx1c2VyXzAxSlE5TlNQM1k2WUQ4NTlFR1BRUzkyNjlDIiwidGltZSI6IjE3NzAyNDg3MTgiLCJleHAiOjE3NzU0MzI3MTgsInR5cGUiOiJzZXNzaW9uIn0.test-signature",
        "refreshToken" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdXRoMHx1c2VyXzAxSlE5TlNQIiwidHlwZSI6InJlZnJlc2gifQ.test-refresh-sig"
      }.to_json
    },
    "codex" => {
      path: "/home/codex/.codex/auth.json",
      content: {
        "auth_mode" => "chatgpt",
        "OPENAI_API_KEY" => nil,
        "tokens" => {
          "id_token" => "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.test-id-token",
          "access_token" => "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3QiLCJ0eXAiOiJKV1QifQ.test-access-token",
          "refresh_token" => "test-codex-refresh-token",
          "account_id" => "user-xxVJrnT5jgBXof5mAWoFlkNo"
        },
        "last_refresh" => Time.now.utc.iso8601
      }.to_json
    },
    "gemini_cli" => {
      path: "/home/gemini/.gemini/oauth_creds.json",
      content: {
        "access_token" => "ya29.a0ATkoCc5XHtest-gemini-access-token",
        "refresh_token" => "1//0ciZ2YJxC1AUWtest-gemini-refresh",
        "scope" => "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/generative-language.retriever",
        "token_type" => "Bearer",
        "id_token" => "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3QifQ.test-gemini-id-token",
        "expiry_date" => (Time.now.to_i + 3600) * 1000
      }.to_json
    }
  }.freeze

  MITM_LOGS = {
    "claude_code" => "",
    "gemini_cli" => "",
    "cursor_cli" => [
      { _source: "http2-logger", direction: "request", scheme: "https", method: "POST",
        host: "api2.cursor.sh", port: 443,
        path: "/agent.v1.AgentService/Run",
        url: "https://api2.cursor.sh/agent.v1.AgentService/Run",
        ts: Time.now.utc.iso8601(6),
        headers: {
          "accept-encoding" => "gzip,br",
          "authorization" => "Bearer eyJhbGciOiJIUzI1NiJ9.test-token",
          "connect-protocol-version" => "1",
          "content-type" => "application/proto",
          "user-agent" => "connect-es/1.6.1",
          "x-cursor-client-type" => "cli",
          "x-cursor-client-version" => "cli-2026.02.13-41ac335",
          "x-ghost-mode" => "true",
          "x-request-id" => "f3b82c20-18aa-4f88-ba0d-c7036521f1e2"
        },
        content_length: 42, body_encoding: "text", body_truncated: false },
      { _source: "http2-logger", direction: "response", status_code: 200,
        host: "api2.cursor.sh",
        path: "/agent.v1.AgentService/Run",
        url: "https://api2.cursor.sh/agent.v1.AgentService/Run",
        ts: (Time.now.utc + 12.5).iso8601(6),
        headers: {
          "Date" => Time.now.utc.httpdate,
          "Content-Type" => "application/proto",
          "Connection" => "close",
          "vary" => "Origin",
          "access-control-allow-credentials" => "true",
          "x-request-id" => "f3b82c20-18aa-4f88-ba0d-c7036521f1e2"
        },
        content_length: 0, body_encoding: "text", body_truncated: false }
    ].map(&:to_json).join("\n") + "\n",
    "codex" => [
      { direction: "request", scheme: "https", method: "GET",
        host: "chatgpt.com", port: 443,
        path: "/backend-api/codex/models?client_version=0.104.0",
        url: "https://chatgpt.com/backend-api/codex/models?client_version=0.104.0",
        ts: Time.now.utc.iso8601(6),
        headers: {
          "version" => "0.104.0",
          "authorization" => "Bearer eyJhbGciOiJSUzI1NiJ9.test-codex-bearer",
          "user-agent" => "codex_cli_rs/0.104.0 (Debian 12.0.0; aarch64) xterm-256color"
        },
        content_length: 0, body_encoding: "text", body_truncated: false },
      { direction: "response", status_code: 200,
        host: "chatgpt.com",
        path: "/backend-api/codex/responses",
        url: "https://chatgpt.com/backend-api/codex/responses",
        ts: (Time.now.utc + 2.3).iso8601(6),
        headers: {
          "Date" => Time.now.utc.httpdate,
          "Content-Type" => "text/event-stream",
          "Connection" => "keep-alive",
          "Server" => "cloudflare",
          "x-oai-request-id" => "f4935b8a-2704-439f-8905-09f00f4aeee1"
        },
        content_length: 0, body_encoding: "text", body_truncated: false,
        body: [
          '{"type":"response.created","response":{"id":"resp_test123","model":"codex-mini-latest","status":"in_progress"}}',
          '{"type":"response.output_item.added","output_index":0,"item":{"type":"message","role":"assistant"}}',
          '{"type":"response.completed","response":{"id":"resp_test123","model":"codex-mini-latest","status":"completed",' \
          '"usage":{"input_tokens":1547,"output_tokens":832,"total_tokens":2379,"cached_tokens":512,"reasoning_tokens":128}}}'
        ].join("\n") }
    ].map(&:to_json).join("\n") + "\n"
  }.freeze

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
