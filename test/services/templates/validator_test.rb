# frozen_string_literal: true

require "test_helper"

class Templates::ValidatorTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/templates/dev-team-sdlc")

  def package(files: nil)
    base = Templates::Package.from_directory(FIXTURE)
    definition = base.definition.deep_dup
    yield definition if block_given?
    Templates::Package.new(definition: definition, files: files || base.files)
  end

  def errors_for(...) = Templates::Validator.new(package(...)).errors

  test "the full-featured fixture is valid and is a project template" do
    assert_empty errors_for
    assert_equal "project", package.kind
  end

  test "the kind follows the most encompassing section present" do
    base = { "format_version" => 1, "namespace" => "acme", "slug" => "x", "version" => 1, "name" => "X" }
    agent = { "key" => "a", "name" => "a", "title" => "A", "persona" => "P." }
    server = { "key" => "s", "custom" => { "name" => "S", "transport" => "http", "url" => "https://mcp.example.com" } }

    assert_equal "agent", Templates::Package.new(definition: base.merge("agents" => [ agent ], "mcp_servers" => [ server ])).kind
    assert_equal "skill", package { |d| d.slice!("format_version", "namespace", "slug", "version", "name", "skills") }.kind
    assert_equal "connector", Templates::Package.new(definition: base.merge("mcp_servers" => [ server ])).kind
  end

  test "a template that installs nothing is refused" do
    empty = Templates::Package.new(definition: { "format_version" => 1, "namespace" => "acme", "slug" => "x", "version" => 1, "name" => "X" })

    assert_includes Templates::Validator.new(empty).errors,
                    "the template installs nothing — add at least one agent, skill, server, tool, board or workflow"
  end

  test "validate! raises with every error listed" do
    error = assert_raises(Templates::Validator::InvalidPackage) do
      Templates::Validator.validate!(package { |d| d.delete("slug") })
    end
    assert_match(/slug/, error.message)
  end

  test "schema errors come with a pointer and stop the semantic checks" do
    errors = errors_for { |d| d["surprise"] = true }

    assert_equal 1, errors.size
    assert_match(%r{\A/surprise: .*disallowed additional property}, errors.first)
  end

  test "a template may require only an integration a user can connect, or a tracker" do
    [ *Integration::CONNECTABLE_PROVIDERS, Trackers::CAPABILITY ].each do |provider|
      errors = errors_for do |d|
        d["requires"]["integrations"] = [ provider ]
        d["tools"].first["requires_integration"] = provider
      end
      assert_empty errors, provider
    end

    errors = errors_for do |d|
      d["requires"]["integrations"] = [ "trello" ]
      d["tools"].first["requires_integration"] = "trello"
    end
    assert_match(%r{/requires/integrations/0}, errors.join)
    assert_match(%r{/tools/0/requires_integration}, errors.join)
  end

  test "a docker image without a digest is refused" do
    errors = errors_for { |d| d["tools"].first["docker_image"] = "ghcr.io/acme/runner:latest" }
    assert_match(%r{/tools/0}, errors.join)
  end

  test "references between sections must resolve" do
    errors = errors_for do |d|
      step = d["workflows"].first["steps"].first
      step["agent"] = "ghost"
      step["skills"] = [ "missing_skill" ]
      d["workflows"].first["base"]["repositories"] = [ "other_repo" ]
      d["triggers"].first["column"] = "nowhere"
    end

    assert_includes errors, "workflow delivery step design agent: unknown key ghost"
    assert_includes errors, "workflow delivery step design skills: unknown key missing_skill"
    assert_includes errors, "workflow delivery base.repositories: unknown key other_repo"
    assert_includes errors, "triggers[0] column: unknown key nowhere"
  end

  test "a chat trigger names its messenger" do
    workflow = package.definition["workflows"].first["key"]
    errors = errors_for do |d|
      d["triggers"] = [ { "kind" => "chat", "workflow" => workflow },
                        { "kind" => "chat", "workflow" => workflow, "chat_provider" => "teams" } ]
    end

    assert_equal [ "triggers[0]: a chat trigger needs chat_provider" ], errors.grep(/triggers/)
  end

  test "a cycle in depends_on is refused" do
    errors = errors_for { |d| d["workflows"].first["steps"].first["depends_on"] = [ "implement" ] }
    assert_includes errors, "workflow delivery: depends_on has a cycle"
  end

  test "duplicate keys are refused" do
    errors = errors_for { |d| d["agents"] << d["agents"].first.dup }
    assert_includes errors, "agents: duplicate key architect"
  end

  test "a config item that is used but never declared is refused" do
    errors = errors_for { |d| d["mcp_servers"].last["custom"]["headers"]["X-Region"] = "config_item:SENTRY_REGION" }
    assert_includes errors, "config item SENTRY_REGION is used but not declared in variables or requires.secrets"
  end

  test "a literal MCP header value is refused, even a harmless-looking one" do
    errors = errors_for { |d| d["mcp_servers"].last["custom"]["headers"]["Authorization"] = "Bearer sk-live-123" }
    assert(errors.any? { |e| e.include?("headers.Authorization: must be a config_item:NAME reference") })
  end

  test "an auth-scheme prefix in front of a reference is allowed" do
    assert_empty(errors_for { |d| d["mcp_servers"].last["custom"]["headers"]["Authorization"] = "Bearer config_item:SENTRY_ORG" })
  end

  test "inputs must be declared and may only appear in substituted fields" do
    errors = errors_for do |d|
      d["agents"].first["persona"] = "Speaks {{inputs.tone}}."
      d["workflows"].first["name"] = "Delivery {{inputs.default_branch}}"
    end

    assert_includes errors, "agents.0.persona: unknown input tone"
    assert_includes errors, "workflows.0.name: {{inputs.*}} is not substituted in this field"
  end

  test "a select input's default must be one of its options" do
    errors = errors_for { |d| d["inputs"].last["default"] = "French" }
    assert_includes errors, "input review_language: default is not one of its options"
  end

  test "a snapshot that does not match its hash is refused" do
    files = Templates::Package.from_directory(FIXTURE).files.merge("snapshots/skills/code-review.md" => "tampered")
    assert_includes errors_for(files: files), "file snapshots/skills/code-review.md does not match its sha256"
  end

  test "an authored SKILL.md must parse and carry a valid name" do
    files = Templates::Package.from_directory(FIXTURE).files.merge(
      "skills/house-style/SKILL.md" => "---\nname: House Style\ndescription: Rules.\n---\n\nBody.\n"
    )

    assert_includes errors_for(files: files),
                    'skills/house-style/SKILL.md: name "House Style" must be lowercase words joined by dashes'
    assert(errors_for(files: files.merge("skills/house-style/SKILL.md" => "no frontmatter")).any? { |e| e.include?("frontmatter") })
  end

  test "a connector must name a target in its snapshot, with its package release pinned" do
    files = Templates::Package.from_directory(FIXTURE).files
    manifest = JSON.parse(files["snapshots/connectors/remote.json"])
    manifest["targets"] << { "id" => "package:npm:x", "kind" => "package", "supported" => true, "version_pinned" => false }
    unpinned = files.merge("snapshots/connectors/remote.json" => JSON.generate(manifest))
    retarget = lambda do |target|
      lambda do |d|
        server = d["mcp_servers"].first["connector"]
        server["target"] = target
        server["manifest"]["sha256"] = Digest::SHA256.hexdigest(unpinned["snapshots/connectors/remote.json"])
      end
    end

    assert_includes errors_for(files: unpinned, &retarget.call("nowhere")), "connector linear: target nowhere is not in its manifest"
    assert(errors_for(files: unpinned, &retarget.call("package:npm:x")).any? { |e| e.include?("release is not pinned") })
  end

  test "an asset name that could leave the assets directory is refused" do
    errors = errors_for { |d| d["assets"].first["name"] = "../../root/.bashrc" }

    assert(errors.any? { |e| e.start_with?("asset ") && e.include?("../../root/.bashrc") }, errors.inspect)
    assert_empty(errors_for { |d| d["assets"].first["name"] = "guides/standards.md" })
  end

  test "a referenced file missing from the package is refused" do
    files = Templates::Package.from_directory(FIXTURE).files.except("assets/coding-standards.md")
    assert_includes errors_for(files: files), "file assets/coding-standards.md is referenced but missing from the package"
  end

  # Steps and the MCP tools take their levels from config/agent_runtimes.json; the
  # template schema lists them by hand, so a level added to the registry must be added
  # here too, or a template carrying it fails validation on install.
  test "the template schema's reasoning-effort levels are the registry's" do
    schema = JSON.parse(Templates::Package::SCHEMA_PATH.read)
    levels = schema.dig("properties", "workflows", "items", "properties", "steps", "items", "properties",
                        "reasoning_effort", "enum")

    assert_equal AgentRuntime.reasoning_effort_levels.sort, levels.sort
  end

  # Steps take their runtimes from config/agent_runtimes.json; a runtime missing here
  # makes a workflow exported with it fail validation.
  test "the template schema's runtimes are the registry's" do
    schema = JSON.parse(Templates::Package::SCHEMA_PATH.read)
    runtimes = schema.dig("properties", "workflows", "items", "properties", "steps", "items", "properties",
                          "required_agent_runtime", "enum")

    assert_equal AgentRuntime.ids.sort, runtimes.sort
  end

  test "a step's reasoning effort needs its preferred model and runtime" do
    without_model = package do |definition|
      definition["workflows"].first["steps"].first.merge!("required_agent_runtime" => "kiro_cli",
                                                          "reasoning_effort" => "high")
    end
    assert_not_empty Templates::Validator.new(without_model).errors

    complete = package do |definition|
      definition["workflows"].first["steps"].first.merge!("required_agent_runtime" => "kiro_cli",
                                                          "preferred_model" => "claude-opus-5.5",
                                                          "reasoning_effort" => "high")
    end
    assert_empty Templates::Validator.new(complete).errors
  end

  test "a step's reasoning effort must be one its runtime takes for its model" do
    workflow = package.definition["workflows"].first
    label = "workflow #{workflow['key']} step #{workflow['steps'].first['key']} reasoning_effort"
    errors = lambda do |runtime, model, level|
      errors_for do |definition|
        definition["workflows"].first["steps"].first.merge!("required_agent_runtime" => runtime,
                                                            "preferred_model" => model,
                                                            "reasoning_effort" => level)
      end
    end

    assert_equal [ "#{label}: gemini_cli with model gemini-2.5-pro takes no reasoning effort" ],
                 errors.call("gemini_cli", "gemini-2.5-pro", "low")
    assert_equal [ "#{label}: xhigh is not available for kiro_cli with model claude-sonnet-4.6 " \
                   "(choose one of: low, medium, high, max)" ],
                 errors.call("kiro_cli", "claude-sonnet-4.6", "xhigh")
    assert_empty errors.call("gemini_cli", "gemini-3-pro", "low")
  end

  test "the installer refuses a step whose runtime and model take no such reasoning effort" do
    invalid = package do |definition|
      definition["workflows"].first["steps"].first.merge!("required_agent_runtime" => "gemini_cli",
                                                          "preferred_model" => "gemini-2.5-pro",
                                                          "reasoning_effort" => "low")
    end

    error = assert_raises(Templates::Validator::InvalidPackage) { Templates::Validator.validate!(invalid) }
    assert_match(/reasoning_effort: gemini_cli with model gemini-2\.5-pro takes no reasoning effort/, error.message)
  end
end
