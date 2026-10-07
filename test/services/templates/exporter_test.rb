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
    Templates::Exporter.new(project: project, namespace: "acme", slug: "exported", name: "Exported", include_assets: true, **options).call
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

  test "references travel as package keys and come back as the copy's ids" do
    workflow = @source.workflows.sole
    first, second = workflow.steps.order(:position).to_a.first(2)
    sentry = @source.mcp_servers.find_by!(name: "Sentry")
    first.update!(output_asset_specs: [ { "name" => "triage.md" } ])
    second.update!(mcp_server_ids: second.mcp_server_ids | [ sentry.id ], depends_on_step_ids: [ first.id ],
                   instructions: "Read {{output:#{first.id}:triage.md}} from {{step:#{first.id}}}; ask {{mcp:#{sentry.id}}}.")

    result = export
    exported = result.package.definition["workflows"].sole["steps"].find { |step| step["name"] == second.name }

    assert_match(/\ARead \{\{output:[a-z][a-z0-9_]*:triage\.md\}\} from \{\{step:[a-z][a-z0-9_]*\}\}; ask \{\{mcp:[a-z][a-z0-9_]*\}\}\.\z/,
                 exported["instructions"])

    copy = install(result.package).project
    copy_first, copy_second = copy.workflows.sole.steps.order(:position).to_a.first(2)
    copy_sentry = copy.mcp_servers.find_by!(name: "Sentry")
    assert_equal "Read {{output:#{copy_first.id}:triage.md}} from {{step:#{copy_first.id}}}; ask {{mcp:#{copy_sentry.id}}}.",
                 copy_second.instructions
  end

  test "a skill's extra files travel with it" do
    skill = @source.skills.find_by!(name: "house-style")
    skill.update!(files: skill.files.merge("examples/good.rb" => "def small = 1\n"))

    result = export
    entry = result.package.section("skills").find { |s| s["path"] }

    assert_equal [ "examples/good.rb" ], entry["files"].pluck("path")
    copy = install(result.package).project.skills.find_by!(name: "house-style")
    assert_equal "def small = 1\n", copy.files["examples/good.rb"]
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

  test "a tracker trigger exports for any tracker of the installing project" do
    integration = create(:integration, :azure_devops, :active, company: @company, project: @source)
    tracker = create(:project_tracker, integration: integration)
    create(:trigger_binding, project: @source, workflow: @source.workflows.first, project_tracker: tracker,
                             event_type: "tracker.issue.status_changed", aixle_changes: "other_workflows", enabled: false)

    result = export

    entry = result.package.definition["triggers"].find { |t| t["kind"] == "tracker" }
    assert_equal [ "tracker.issue.status_changed", "other_workflows" ], [ entry["event_type"], entry["aixle_changes"] ]
    assert_match(/any tracker of the installing project/, result.notes.join)
  end

  test "a chat trigger exports its messenger as a requirement and installs listening to it" do
    create(:integration, provider: :teams, status: :active, company: @company, project: nil)
    create(:trigger_binding, project: @source, workflow: @source.workflows.first, event_type: "chat.message",
                             filter_predicate: { "provider" => "teams", "text" => { "op" => "starts_with", "value" => "deploy" } },
                             status_reporting: "lifecycle", enabled: false)

    result = export

    entry = result.package.definition["triggers"].find { |t| t["kind"] == "chat" }
    assert_equal [ "teams", "lifecycle" ], entry.values_at("chat_provider", "status_reporting")
    assert_equal({ "text" => { "op" => "starts_with", "value" => "deploy" } }, entry["filter_predicate"])
    assert_includes result.package.definition.dig("requires", "integrations"), "teams"
    copy = install(result.package).project
    installed = TriggerBinding.find_by!(project: copy, event_type: "chat.message")
    assert_equal [ "teams", "lifecycle" ], [ installed.chat_provider, installed.status_reporting ]
  end

  test "a workflow using a tracker tool exports a tracker requirement the installer can resolve" do
    tool = create(:tool, :system, name: "tracker_update_issue", requires_integration: Trackers::CAPABILITY)
    step = @source.workflows.sole.steps.order(:position).first
    step.update!(tool_ids: step.tool_ids + [ tool.id ])

    result = export

    assert_includes result.package.definition.dig("requires", "integrations"), Trackers::CAPABILITY
    item = install(result.package).install.setup_items.find_by!(ref: "integration:#{Trackers::CAPABILITY}")
    assert_equal "Connect a task tracker (Jira or Azure DevOps)", Templates::Presenter.setup_item(item)[:label]
  end
end
