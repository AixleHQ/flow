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

  test "a referenced file missing from the package is refused" do
    files = Templates::Package.from_directory(FIXTURE).files.except("assets/coding-standards.md")
    assert_includes errors_for(files: files), "file assets/coding-standards.md is referenced but missing from the package"
  end
end
