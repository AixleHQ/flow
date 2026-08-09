# frozen_string_literal: true

module ContainerRuntime
  # Canonical in-memory fake for the container runtime boundary (docs/testing.md §4,
  # R3). It is a real ContainerRuntime::BaseRuntime implementing the documented
  # interface against an in-memory virtual filesystem + command router — replacing
  # the old StubSupport machinery (Docker::Container/Kubeclient vendor stubs +
  # any_instance/define_method monkeypatching + manual teardown).
  #
  # Callers obtain it through the existing `ContainerRuntime.build` seam; tests
  # inject it via `stub_container_runtime` (StubSupport), which stubs
  # `ContainerRuntime.build` to return an instance — no per-test vendor stubbing.
  #
  # `exec` returns the documented contract [stdout_lines, stderr_lines, exit_code]
  # (arrays), which callers consume as `result[0].join` / `result[2].zero?`.
  class FakeRuntime < BaseRuntime
    FULL_ID = "abcdef1234567890abcdef"

    # Mirrors ContainerRuntime::KubernetesRuntime::SESSION_RESOURCE_KINDS — the
    # object kinds one session owns, in the deletion order the BaseRuntime
    # garbage-collection contract promises.
    SESSION_RESOURCE_KINDS = %w[IngressRoute Middleware Service Pod].freeze

    # Lightweight container handle: create_container returns this; the runtime's
    # own methods key off the in-memory FS, not the handle, so it only carries id.
    Handle = Struct.new(:id) do
      def is_a?(klass)
        klass == FakeRuntime::Handle || super
      end
    end

    attr_reader :fs, :execs, :agent_type, :deleted_session_resources

    def initialize(agent_type: "claude_code", filesystem: nil)
      @agent_type = agent_type
      @fs = filesystem || build_filesystem(agent_type)
      @execs = []
      @exec_failures = []
      @default_container_status = :running
      @container_statuses = {}
      @session_resources = []
      @deleted_session_resources = []
      @undeletable_resource_names = []
    end

    # Liveness injection: answer #container_status with `status` for one container
    # id, or for every container when `container_id:` is omitted. Mirrors the
    # vocabulary documented on BaseRuntime#container_status. Passing an exception
    # instance makes the lookup raise instead (both real runtimes swallow control
    # plane errors into :unknown, so this models a caller-visible failure).
    def set_container_status(status, container_id: nil)
      if container_id.nil?
        @default_container_status = status
      else
        @container_statuses[container_id.to_s] = status
      end
      self
    end

    # Command failure injection: register a substring of the command line and
    # the failure to answer it with. Everything else keeps succeeding, so the
    # default behavior is unchanged for callers that never call this.
    def fail_exec(substring, stderr: "", exit_code: 1)
      @exec_failures << { substring: substring, stderr: stderr, exit_code: exit_code }
    end

    # -- Lifecycle ------------------------------------------------------------

    def pull_image(image)
      { status: :cached, image: image, duration_seconds: 0 }
    end

    def create_container(_spec)
      Handle.new(FULL_ID)
    end

    def start_container(id)
      resolve_container(id)
    end

    def wait_for_ready(_id, _ports = [])
      true
    end

    def stop_container(_id, _timeout = nil, _options = {})
      nil
    end

    def remove_container(_id, _options = {})
      nil
    end

    def remove_image(_image)
      nil
    end

    def image_digest(image)
      "#{image}@sha256:#{'a' * 64}"
    end

    # -- Execution ------------------------------------------------------------

    def exec(_id, cmd, _opts = {})
      @execs << cmd
      failure = @exec_failures.find { |f| command_string(cmd).include?(f[:substring]) }
      return [ [ "" ], [ failure[:stderr] ], failure[:exit_code] ] if failure

      [ [ resolve_command(cmd) ], [ "" ], 0 ]
    end

    # -- File I/O -------------------------------------------------------------

    def write_file(_id, path, content, mode: 0o644, uid: 0, gid: 0)
      @fs[path] = content
      true
    end

    def read_file(_id, path)
      @fs[path]
    end

    # -- Introspection --------------------------------------------------------

    def resolve_container(container_id)
      return container_id if container_id.is_a?(Handle)

      Handle.new(container_id.to_s)
    end

    def container_identifier(container)
      return nil if container.blank?
      return container if container.is_a?(String)

      container.respond_to?(:id) ? container.id.to_s[0..11] : container.to_s
    end

    def container_status(id)
      key = id.respond_to?(:id) ? id.id.to_s : id.to_s
      status = @container_statuses.fetch(key, @default_container_status)
      raise status if status.is_a?(Exception)

      status
    end

    def wait_container(_id, _timeout = nil)
      { "StatusCode" => 0 }
    end

    def container_logs(_id, stdout: true, stderr: true)
      { stdout: "", stderr: "" }
    end

    # -- Garbage collection ---------------------------------------------------

    # Seed the objects the runtime is holding. `route_token:` is the key the
    # sweeper reconciles against TerminalSession; `created_at:` is what its
    # minimum-age guard reads. Kinds are handed back in the deletion order the
    # BaseRuntime contract promises.
    def seed_session_resources(route_token:, created_at:, kinds: SESSION_RESOURCE_KINDS, namespace: "aixle-project-1", name_prefix: nil)
      prefix = name_prefix || (route_token.present? ? "terminal-#{route_token}" : "aixle-tool")

      Array(kinds).map do |kind|
        resource = ContainerRuntime::SessionResource.new(
          kind: kind,
          name: "#{prefix}-#{kind.downcase}",
          namespace: namespace,
          route_token: route_token,
          created_at: created_at
        )
        @session_resources << resource
        resource
      end
    end

    # Make one object refuse to be deleted, so callers can exercise the
    # failure-counting path without stubbing the runtime.
    def fail_session_resource_delete(name)
      @undeletable_resource_names << name
    end

    def list_session_resources
      @session_resources.dup
    end

    def delete_session_resource(resource)
      return false if @undeletable_resource_names.include?(resource.name)

      @session_resources.delete(resource)
      @deleted_session_resources << resource
      true
    end

    private

    # Command router — maps the handful of shell commands the strategies run to
    # deterministic output backed by the virtual FS (ports StubSupport.resolve_command).
    def command_string(cmd)
      cmd.is_a?(Array) ? cmd.join(" ") : cmd.to_s
    end

    def resolve_command(cmd)
      cmd_str = command_string(cmd)

      return "open\n" if cmd_str.include?("echo 'open'")
      return "0\n" if cmd_str.include?(".agent_done")

      if cmd_str.include?("find") && cmd_str.include?("/workspace/outputs")
        return @fs.keys.select { |k| k.start_with?("/workspace/outputs/") }.join("\n")
      end

      if (m = cmd_str.match(/cat\s+(\S+)/))
        return @fs[m[1]] || ""
      end

      ""
    end

    # -- Per-agent virtual filesystem with realistic fixture data -------------

    def build_filesystem(agent_type)
      auth = AUTH_CONFIGS.fetch(agent_type)
      log = MITM_LOGS.fetch(agent_type, "")

      fs = {}
      fs[auth[:path]] = auth[:content]
      auth[:extra_files]&.each { |path, content| fs[path] = content }
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
        path: "/home/gemini/.gemini/settings.json",
        content: {
          "security" => { "auth" => { "selectedType" => "gemini-api-key" } }
        }.to_json,
        extra_files: {
          "/home/gemini/.gemini/gemini-credentials.json" =>
            "9b744f9a5cab60c42a69a50f:04da5baafc2bbc778085937044112f07:2a4afe6a9c8969be3dfa312251b49ef9807b3271175bedacfc2f0f319176956cb144525368f4b9468db780e8d419f6e05ea7881b34370411bd33bdf7b913045dc9f2279f15c5b4bef8933933642f644487b5d141790619784e43c202c64016451d92"
        }
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
  end
end
