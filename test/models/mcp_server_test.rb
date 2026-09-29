# frozen_string_literal: true

require "test_helper"

class MCPServerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "rejects company scope for custom MCP server" do
    server = MCPServer.new(
      name: "context7",
      url: "https://mcp.context7.io",
      transport: "sse",
      kind: "custom",
      scope: @company
    )

    assert_not server.valid?
    assert_includes server.errors[:scope_type], "must be a project"
  end

  test "creates valid custom MCP server with project scope" do
    server = MCPServer.new(
      name: "tavily",
      url: "https://mcp.tavily.com",
      transport: "sse",
      kind: "custom",
      scope: @project
    )

    assert server.valid?
    assert server.save
  end

  test "allows a free-form name with no format constraint" do
    # The lowercase protocol identifier is derived at config time (config_key), so
    # the name itself accepts spaces, capitals and punctuation verbatim.
    server = MCPServer.new(
      name: "My Fancy Server!",
      url: "https://example.com",
      kind: "custom",
      scope: @project
    )

    assert server.valid?, server.errors.full_messages.to_sentence
    assert server.save
    assert_equal "My Fancy Server!", server.reload.name
  end

  test "config_key derives a lowercase protocol identifier from the name" do
    assert_equal "context7", MCPServer.config_key_for("Context7")
    assert_equal "my_fancy_server", MCPServer.config_key_for("My Fancy Server!")
    assert_equal "playwright_browser", MCPServer.config_key_for("Playwright  Browser")
    # Names already within [a-z0-9_-] (e.g. existing slugs) pass through unchanged.
    assert_equal "aixle-tools", MCPServer.config_key_for("aixle-tools")

    server = MCPServer.new(name: "My Fancy Server!")
    assert_equal "my_fancy_server", server.config_key
  end

  test "validates name uniqueness within scope" do
    MCPServer.create!(
      name: "context7",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: @project
    )

    duplicate = MCPServer.new(
      name: "context7",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @project
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "allows same name in different scopes" do
    other_project = create(:project, company: @company, owner: @user)

    MCPServer.create!(
      name: "context7",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: other_project
    )

    project_server = MCPServer.new(
      name: "context7",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @project
    )

    assert project_server.valid?
  end

  test "custom server requires scope" do
    server = MCPServer.new(
      name: "test",
      url: "https://example.com",
      kind: "custom"
    )

    assert_not server.valid?
    assert_includes server.errors[:scope], "can't be blank"
  end

  test "custom server requires url" do
    server = MCPServer.new(
      name: "test",
      kind: "custom",
      scope: @project
    )

    assert_not server.valid?
    assert_includes server.errors[:url], "can't be blank"
  end

  test "internal server does not require scope or url" do
    server = MCPServer.new(
      name: "aixle-tools",
      kind: "internal"
    )

    assert server.valid?
  end

  test "for_project scope returns only that project's servers" do
    other_project = create(:project, company: @company, owner: @user)

    project_server = MCPServer.create!(
      name: "project-server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    other_server = MCPServer.create!(
      name: "other-server",
      url: "https://other.example.com",
      kind: "custom",
      scope: other_project
    )

    assert_includes MCPServer.for_project(@project), project_server
    assert_not_includes MCPServer.for_project(@project), other_server
  end

  test "visible_for_project returns internal and project servers only" do
    internal_server = MCPServer.create!(
      name: "aixle-tools",
      kind: "internal"
    )

    project_server = MCPServer.create!(
      name: "project-server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    other_project = create(:project, company: @company, owner: @user)
    other_server = MCPServer.create!(
      name: "other-server",
      url: "https://other.example.com",
      kind: "custom",
      scope: other_project
    )

    result = MCPServer.visible_for_project(@project)

    assert_includes result, internal_server
    assert_includes result, project_server
    assert_not_includes result, other_server
  end

  test "visible_for_project returns ActiveRecord::Relation" do
    result = MCPServer.visible_for_project(@project)
    assert_kind_of ActiveRecord::Relation, result
  end

  # ====================================================================
  # SSRF Protection
  # ====================================================================

  test "rejects private IPv4 addresses" do
    %w[http://10.0.0.1/mcp http://172.16.0.1/mcp http://192.168.1.1/mcp].each do |private_url|
      server = MCPServer.new(
        name: "test-ssrf", url: private_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{private_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects loopback addresses" do
    %w[http://127.0.0.1/mcp http://127.0.0.2:8080/mcp].each do |loopback_url|
      server = MCPServer.new(
        name: "test-ssrf", url: loopback_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{loopback_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects link-local addresses (cloud metadata)" do
    server = MCPServer.new(
      name: "test-ssrf", url: "http://169.254.169.254/latest/meta-data/",
      kind: "custom", scope: @project
    )
    assert_not server.valid?
    assert_includes server.errors[:url], "cannot point to private or internal network addresses"
  end

  test "rejects blocked hostnames" do
    %w[http://localhost:3000/mcp http://metadata.google.internal/mcp http://metadata.goog/mcp].each do |blocked_url|
      server = MCPServer.new(
        name: "test-ssrf", url: blocked_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{blocked_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{blocked_url}"
    end
  end

  test "rejects non-http schemes" do
    %w[ftp://example.com/mcp file:///etc/passwd javascript:alert(1)].each do |bad_url|
      server = MCPServer.new(
        name: "test-ssrf", url: bad_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{bad_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{bad_url}"
    end
  end

  test "allows valid public URLs" do
    %w[https://mcp.context7.io https://api.tavily.com/mcp http://mcp.example.com:8080/sse].each do |good_url|
      server = MCPServer.new(
        name: "test-valid", url: good_url,
        kind: "custom", scope: @project
      )
      server.valid?
      assert_empty server.errors[:url], "Expected #{good_url} to be valid, got: #{server.errors[:url]}"
    end
  end

  test "internal servers skip URL validation" do
    server = MCPServer.new(
      name: "aixle-internal", kind: "internal"
    )
    assert server.valid?
  end

  # ====================================================================
  # Scopes
  # ====================================================================

  test "enabled scope filters correctly" do
    enabled = MCPServer.create!(
      name: "enabled-server",
      url: "https://enabled.example.com",
      kind: "custom",
      scope: @project,
      enabled: true
    )

    disabled = MCPServer.create!(
      name: "disabled-server",
      url: "https://disabled.example.com",
      kind: "custom",
      scope: @project,
      enabled: false
    )

    assert_includes MCPServer.enabled, enabled
    assert_not_includes MCPServer.enabled, disabled
  end

  # ====================================================================
  # OAuth: auth_type + credential_scope (Phase 3)
  # ====================================================================

  test "auth_type defaults to none and credential_scope to shared" do
    server = MCPServer.new(
      name: "defaults",
      url: "https://mcp.example.com", kind: "custom", scope: @project
    )

    assert_equal "none", server.auth_type
    assert_equal "shared", server.credential_scope
    assert server.auth_type_none?
    assert server.credential_scope_shared?
  end

  test "auth_type predicates" do
    server = MCPServer.new

    server.auth_type = "none"
    assert server.auth_type_none?
    assert_not server.auth_type_static?
    assert_not server.auth_type_oauth?

    server.auth_type = "static"
    assert server.auth_type_static?
    assert_not server.auth_type_none?
    assert_not server.auth_type_oauth?

    server.auth_type = "oauth"
    assert server.auth_type_oauth?
    assert_not server.auth_type_none?
    assert_not server.auth_type_static?
  end

  test "credential_scope predicates" do
    server = MCPServer.new

    server.credential_scope = "shared"
    assert server.credential_scope_shared?
    assert_not server.credential_scope_per_user?

    server.credential_scope = "per_user"
    assert server.credential_scope_per_user?
    assert_not server.credential_scope_shared?
  end

  test "oauth? convenience predicate mirrors auth_type_oauth?" do
    server = MCPServer.new
    server.auth_type = "static"
    assert_not server.oauth?
    server.auth_type = "oauth"
    assert server.oauth?
  end

  test "rejects unknown auth_type / credential_scope values" do
    server = MCPServer.new(
      name: "bad-enum", url: "https://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "bogus", credential_scope: "nobody"
    )

    assert_not server.valid?
    assert server.errors[:auth_type].any?
    assert server.errors[:credential_scope].any?
  end

  test "with_auth_type scope filters by auth_type" do
    oauth_server = MCPServer.create!(
      name: "oauth-srv", url: "https://oauth.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )
    static_server = MCPServer.create!(
      name: "static-srv", url: "https://static.example.com",
      kind: "custom", scope: @project, auth_type: "static"
    )

    result = MCPServer.with_auth_type(:oauth)
    assert_includes result, oauth_server
    assert_not_includes result, static_server
  end

  test "with_credential_scope scope filters by credential_scope" do
    per_user = MCPServer.create!(
      name: "per-user-srv", url: "https://pu.example.com",
      kind: "custom", scope: @project, auth_type: "oauth", credential_scope: "per_user"
    )
    shared = MCPServer.create!(
      name: "shared-srv", url: "https://shared.example.com",
      kind: "custom", scope: @project, auth_type: "oauth", credential_scope: "shared"
    )

    result = MCPServer.with_credential_scope(:per_user)
    assert_includes result, per_user
    assert_not_includes result, shared
  end

  test "oauth server requires https url" do
    server = MCPServer.new(
      name: "oauth-http", url: "http://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )

    assert_not server.valid?
    assert_includes server.errors[:url], "must use https"
  end

  test "oauth server accepts https url" do
    server = MCPServer.new(
      name: "oauth-https", url: "https://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )

    server.valid?
    assert_empty server.errors[:url]
  end

  test "static server does not require https url" do
    server = MCPServer.new(
      name: "static-http", url: "http://mcp.example.com:8080/sse",
      kind: "custom", scope: @project, auth_type: "static"
    )

    server.valid?
    assert_empty server.errors[:url]
  end

  # ---- stdio launch line: one storage shape, whichever path wrote the row ----

  def stdio_server(**attrs)
    MCPServer.new({ name: "stdio-#{SecureRandom.hex(3)}", kind: "custom", scope: @project,
                    transport: "stdio" }.merge(attrs))
  end

  test "a pasted command line is stored split into the executable and its argv" do
    server = stdio_server(command: "npx @playwright/mcp@0.0.41 --headless")

    assert server.save, server.errors.full_messages.to_sentence
    assert_equal "npx", server.command
    assert_equal [ "@playwright/mcp@0.0.41", "--headless" ], server.args
    assert_equal [ "@playwright/mcp@0.0.41", "--headless" ], server.launch_args
  end

  test "a catalog install keeps the argv it was rendered with" do
    server = stdio_server(command: "npx", args: [ "-y", "remote-filesystem-mcp-server@0.1.2" ],
                          connector_name: "io.github.example/remote-fs")

    assert server.save, server.errors.full_messages.to_sentence
    assert_equal "npx", server.command
    assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], server.args
  end

  test "editing the line replaces the stored argv rather than adding to it" do
    server = stdio_server(command: "uvx server-a==1.0.0 --verbose")
    server.save!

    server.update!(command: "uvx server-b==2.0.0")

    assert_equal "uvx", server.command
    assert_equal [ "server-b==2.0.0" ], server.args
  end

  test "saving an unrelated field leaves an already-split line alone" do
    server = stdio_server(command: "npx pkg@1.0.0 --flag")
    server.save!

    server.update!(description: "renamed")

    assert_equal "npx", server.command
    assert_equal [ "pkg@1.0.0", "--flag" ], server.args
  end

  test "command_line rejoins the launch line for the form, quoting only what needs it" do
    server = stdio_server(command: "npx", args: [ "--port=8080", "--title", "my server" ])

    assert_equal 'npx --port=8080 --title "my server"', server.command_line
    assert_equal [ "npx", "--port=8080", "--title", "my server" ], Shellwords.split(server.command_line)
  end

  test "command_line round-trips a quoted argument through a re-save" do
    server = stdio_server(command: 'npx pkg@1.0.0 --title "my server"')
    server.save!

    reparsed = stdio_server(name: "reparsed", command: server.command_line)
    reparsed.save!

    assert_equal server.args, reparsed.args
  end

  # ---- what cannot be launched, refused where the user can still see it ----

  test "rejects an environment assignment in place of the program" do
    server = stdio_server(command: "API_KEY=secret npx pkg")

    assert_not server.valid?
    assert_includes server.errors[:command].to_sentence, "put environment variables in the Env section"
  end

  test "rejects shell operators, which a directly spawned process never sees" do
    server = stdio_server(command: "npx pkg | tee log")

    assert_not server.valid?
    assert_includes server.errors[:command].to_sentence, "without a shell"
  end

  test "rejects a runtime the agent image does not carry" do
    server = stdio_server(command: "docker run -i ghcr.io/example/mcp")

    assert_not server.valid?
    assert_equal [ MCP::ConnectorManifest::UNAVAILABLE_RUNTIMES["docker"] ], server.errors[:command]
  end

  test "rejects an unbalanced quote instead of silently dropping the rest of the line" do
    server = stdio_server(command: 'npx pkg --title "unclosed')

    assert_not server.valid?
    assert_includes server.errors[:command].to_sentence, "unbalanced quote"
  end

  test "an argument that merely contains an operator is not mistaken for one" do
    server = stdio_server(command: 'npx pkg@1.0.0 --filter "a && b"')

    assert server.valid?, server.errors.full_messages.to_sentence
    assert_equal [ "pkg@1.0.0", "--filter", "a && b" ], server.args
  end

  # A row written before the split existed keeps working, and stays editable for a
  # reason that has nothing to do with its command.
  # == Package pins ==

  test "a package runner must name an exact release" do
    [ "npx -y pkg", "npx pkg@latest", "npx pkg@^1.2.0", "uvx mcp-server-git", "uvx mcp-server-git>=0.6",
      "pipx run mcp-server-git", "npx -y -p @scope/pkg mcp-cli" ].each do |line|
      server = stdio_server(name: "floating #{line}", command: line)

      assert_not server.valid?, "#{line} should need a pin"
      assert_match(/must pin/, server.errors[:command].to_sentence)
    end
  end

  test "an exact release, a local path or a URL passes" do
    [ "npx -y @scope/pkg@1.2.3", "npx pkg@2025.8.21 --flag", "npx -y -p @scope/pkg@1.0.0-rc.1 mcp-cli",
      "uvx mcp-server-git==0.6.2", "uvx mcp-server-git@0.6.2", "uvx --from mcp-server-git==0.6.2 mcp-server-git",
      "pipx run mcp-server-git==0.6.2", "pipx run --spec mcp-server-git==0.6.2 mcp-server-git",
      "npx ./local-server", "node server.js", "npx @playwright/mcp --headless", "npx @playwright/mcp@latest" ].each do |line|
      server = stdio_server(name: "pinned #{line}", command: line)

      assert server.valid?, "#{line}: #{server.errors.full_messages.to_sentence}"
    end
  end

  test "an unpinned row that predates the rule can still be edited for an unrelated reason" do
    server = stdio_server(command: "npx pkg@1.0.0")
    server.save!
    server.update_columns(command: "npx", args: [ "pkg" ])

    assert server.reload.update(description: "still here"), server.errors.full_messages.to_sentence
  end

  test "a legacy unsplit row can still be disabled" do
    server = stdio_server(command: "npx legacy-pkg@1.0.0 --flag")
    server.save!
    server.update_columns(command: "npx legacy-pkg@1.0.0 --flag", args: [])

    server.reload
    assert server.update(enabled: false), server.errors.full_messages.to_sentence
    assert_equal [ "legacy-pkg@1.0.0", "--flag" ], server.reload.launch_args
  end

  # --- Secrets: encrypted at rest, bound to their destination ---

  def oauth_server_with_credentials
    server = create(:mcp_server, scope: @project, url: "https://mcp.example.com/mcp", transport: "http",
                                 auth_type: :oauth, headers: { "X-Api-Key" => "k-123456" })
    client = OauthClient.create!(issuer: "https://auth.example.com", authorization_endpoint: "https://auth.example.com/a",
                                 token_endpoint: "https://auth.example.com/t", client_id: "dcr-1", source: "dcr")
    OauthCredential.create!(owner: @project, oauth_client: client, provider: "mcp:mcp.example.com",
                            mcp_server: server, resource: server.url, access_token: "at-1", status: :active)
    server.create_manual_oauth_client!(source: OauthClient::SOURCE_MANUAL, client_id: "manual-1", client_secret: "cs-1")
    server
  end

  def stored_row(server)
    MCPServer.connection.select_one("SELECT headers, env, encrypted_headers, encrypted_env FROM mcp_servers WHERE id = #{server.id}")
  end

  test "header and env values are stored encrypted, never as plaintext" do
    server = create(:mcp_server, scope: @project, headers: { "Authorization" => "Bearer s3cret-token" })
    server.update!(env: { "API_KEY" => "env-s3cret" })

    row = stored_row(server)
    assert_equal({}, JSON.parse(row["headers"]))
    assert_equal({}, JSON.parse(row["env"]))
    assert_not_includes row["encrypted_headers"], "s3cret-token"
    assert_not_includes row["encrypted_env"], "env-s3cret"
    assert_equal({ "Authorization" => "Bearer s3cret-token" }, server.reload.headers)
    assert_equal({ "API_KEY" => "env-s3cret" }, server.env)
  end

  test "once purpose binding is on, a ciphertext moved into the other column does not decrypt" do
    Settings.encryption[:bind_purpose] = true
    server = create(:mcp_server, scope: @project, headers: { "Authorization" => "Bearer s3cret-token" })
    server.update_columns(encrypted_env: server.encrypted_headers)

    assert_raises(Encryptable::DecryptionError) { server.reload.env }
  ensure
    Settings.encryption[:bind_purpose] = false
  end

  test "a plaintext copy written by older code is the newest and wins" do
    server = create(:mcp_server, scope: @project, headers: { "Authorization" => "Bearer old" })
    server.update_columns(headers: { "Authorization" => "Bearer written-by-old-code" })

    assert_equal({ "Authorization" => "Bearer written-by-old-code" }, server.reload.headers)
  end

  test "moving to another origin drops the stored values and the OAuth connections" do
    server = oauth_server_with_credentials

    server.update!(url: "https://attacker.example.net/mcp")

    server.reload
    assert_equal({}, server.headers)
    assert_nil server.encrypted_headers
    assert_empty server.oauth_credentials
    assert_nil server.manual_oauth_client
  end

  test "a new path, a new transport on the same origin, or a rename keeps them" do
    server = oauth_server_with_credentials

    server.update!(url: "https://mcp.example.com/v2/mcp")
    server.update!(transport: "sse")
    server.update!(description: "renamed")

    server.reload
    assert_equal({ "X-Api-Key" => "k-123456" }, server.headers)
    assert_equal 1, server.oauth_credentials.count
    assert server.manual_oauth_client
  end

  test "values supplied in the same save as the move are the ones kept" do
    server = create(:mcp_server, scope: @project, url: "https://mcp.example.com/mcp",
                                 headers: { "X-Api-Key" => "old", "X-Other" => "old-2" })

    server.update!(url: "https://new.example.org/mcp", headers: { "X-Api-Key" => "new-value" })

    assert_equal({ "X-Api-Key" => "new-value" }, server.reload.headers)
  end

  test "a stdio server's env is dropped when a different package is launched, not when the line is resubmitted" do
    server = create(:mcp_server, :stdio_transport, scope: @project, command: "npx -y @scope/good-mcp@1.2.0",
                                                   env: { "TOKEN" => "t-123456" })

    server.update!(command: "npx -y @scope/good-mcp@1.2.0")
    assert_equal({ "TOKEN" => "t-123456" }, server.reload.env)

    server.update!(command: "npx -y @evil/exfiltrate@6.6.6")
    assert_equal({}, server.reload.env)
  end

  test "lists the config items its values reference" do
    server = create(:mcp_server, scope: @project,
                                 headers: { "Authorization" => "Bearer config_item:API_TOKEN", "X-Plain" => "literal" })
    server.update!(env: { "DB" => "postgres://config_item:DB_USER@host" })

    assert_equal %w[API_TOKEN DB_USER], server.reload.config_item_refs
  end

  test "purging encrypts what older code left as plaintext and clears every plaintext copy" do
    server = create(:mcp_server, scope: @project)
    server.update_columns(headers: { "Authorization" => "Bearer legacy" }, env: { "K" => "legacy-env" })

    assert_equal 1, MCPServer.purge_plaintext_secrets!

    row = stored_row(server)
    assert_equal({}, JSON.parse(row["headers"]))
    assert_equal({}, JSON.parse(row["env"]))
    assert_equal({ "Authorization" => "Bearer legacy" }, server.reload.headers)
    assert_equal({ "K" => "legacy-env" }, server.env)
    assert_equal 0, MCPServer.purge_plaintext_secrets!
  end

  test "the masked views show which keys are set, never the values" do
    server = create(:mcp_server, scope: @project, headers: { "Authorization" => "Bearer s3cret-token" })

    assert_equal({ "Authorization" => "••••••" }, server.masked_headers)
    assert_equal({}, server.masked_env)
  end
end
