# frozen_string_literal: true

require "test_helper"

class Templates::ExporterTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :employee, :onboarding_completed)
    @company = @user.companies.first
    create(:tool, :system, name: "board_add_comment")
    package = Templates::Package.from_directory(Rails.root.join("test/fixtures/files/templates/dev-team-sdlc"))
    @source = install(package, secrets: { "SENTRY_TOKEN" => "tok-1" }).project
  end

  def install(package, key: SecureRandom.hex(4), **options)
    template = CatalogTemplate.new.assign_package(package, commit_sha: SecureRandom.hex(20)).tap(&:save!)
    Templates::Installer.new(catalog_template: template, user: @user, target: { company: @company },
                             idempotency_key: key, **options).apply
  end

  def export(project = @source, **options)
    Templates::Exporter.new(project: project, slug: "exported", name: "Exported", include_assets: true, **options).call
  end

  test "an installed template exports to a valid package that installs again the same way" do
    result = export

    definition = result.package.definition
    assert_equal "project", result.package.kind
    assert_equal({ "name" => "SENTRY_ORG", "value" => "acme" }, definition["variables"].find { |v| v["name"] == "SENTRY_ORG" })
    assert_equal [ "SENTRY_TOKEN" ], definition.dig("requires", "secrets").pluck("name")
    assert_not_includes result.template_yaml, "tok-1"
    registry = definition["skills"].find { |s| s["registry"] }
    assert_equal "acme/skills@code-review", registry["registry"]
    assert_equal "app.linear/linear", definition["mcp_servers"].find { |s| s["connector"] }.dig("connector", "name")
    assert_equal [ "platform" ], definition["tools"].select { |t| t["platform"] }.map { |t| t.keys - [ "key" ] }.flatten.uniq
    assert_equal %w[column schedule], definition["triggers"].pluck("kind")
    assert_equal "manual", definition["triggers"].first["trigger_mode"], "exports what the project runs now"

    copy = install(result.package).project
    assert_equal @source.board.board_columns.pluck(:name), copy.board.board_columns.pluck(:name)
    assert_equal @source.workflows.sole.steps.order(:position).pluck(:name, :instructions),
                 copy.workflows.sole.steps.order(:position).pluck(:name, :instructions)
    assert_equal @source.agents.pluck(:name, :persona), copy.agents.pluck(:name, :persona)
  end

  test "a literal MCP header value aborts the export and names the server" do
    @source.mcp_servers.find_by!(name: "Sentry").update!(headers: { "Authorization" => "Bearer sk-live-123" })

    error = assert_raises(Templates::Exporter::ExportError) { export }

    assert_match(/MCP server Sentry: Authorization holds a literal value/, error.message)
  end

  test "an image that is not pinned by digest aborts the export" do
    @source.tools.find_by!(name: "run_tests").update!(docker_image: "ghcr.io/acme/runner:latest")

    error = assert_raises(Templates::Exporter::ExportError) { export }
    assert_match(/not pinned by digest/, error.message)
  end

  test "inherit_all_project_resources is flattened into explicit lists" do
    workflow = @source.workflows.sole
    workflow.update!(config: workflow.config.merge("inherit_all_project_resources" => true))

    result = export

    base = result.package.definition["workflows"].first["base"]
    assert_equal @source.mcp_servers.count, base["mcp_servers"].size
    assert(result.notes.any? { |note| note.include?("inherited every project resource") })
  end

  test "a single agent exports on its own as an agent template" do
    agent = @source.agents.find_by!(name: "architect")

    result = export(workflow_ids: [], agent_ids: [ agent.id ], include_board: false, include_assets: false)

    assert_equal "agent", result.package.kind
    assert_equal [ "architect" ], result.package.section("agents").pluck("name")
    assert_empty result.package.section("workflows")
  end

  test "exporting some workflows without the board leaves column triggers out" do
    result = export(include_board: false)

    assert_nil result.package.board
    assert_equal [ "schedule" ], result.package.section("triggers").pluck("kind")
    assert_equal "workflow", result.package.kind
  end
end
