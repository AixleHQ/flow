# frozen_string_literal: true

module Templates
  # Plain-hash views of catalog entries, plans and checklists, shared by the web
  # pages and the personal MCP so both describe a template the same way.
  module Presenter
    SECTION_LABELS = {
      "agents" => "agents", "skills" => "skills", "tools" => "tools", "mcp_servers" => "MCP servers",
      "assets" => "assets", "workflows" => "workflows", "triggers" => "triggers"
    }.freeze

    module_function

    def summary(template)
      package = template.to_package
      {
        slug: template.slug, name: template.name, summary: template.summary, kind: template.kind,
        version: template.version, commit_sha: template.commit_sha, categories: template.categories,
        install_count: template.install_count, requires: requires(package), includes: includes(package)
      }
    end

    def detail(template)
      package = template.to_package
      summary(template).merge(
        readme: template.readme, setup: template.setup_markdown,
        inputs: package.inputs.map { |i| i.slice("key", "label", "description", "type", "options", "default", "required") },
        contents: contents(package),
        board_columns: Array(package.board&.dig("columns")).pluck("name"),
        revoked: template.revoked?, revocation_reason: template.revocation_reason,
        runs_third_party_images: package.section("tools").any? { |t| t["docker_image"] }
      )
    end

    def requires(package)
      {
        integrations: Array(package.requires["integrations"]),
        repositories: Array(package.requires["repositories"]).map { |r| r.slice("key", "purpose") },
        secrets: package.secrets.map { |s| s.slice("name", "description", "prompt_at_install") }
      }
    end

    # Counts per section, for list rows.
    def includes(package)
      counts = SECTION_LABELS.keys.to_h { |section| [ section, package.section(section).size ] }
      counts["columns"] = Array(package.board&.dig("columns")).size
      counts["steps"] = package.section("workflows").sum { |w| w["steps"].size }
      counts.reject { |_, n| n.zero? }
    end

    # Names per section, for the detail page's "what gets created".
    def contents(package)
      {
        agents: package.section("agents").pluck("name"),
        skills: package.section("skills").map { |s| { name: Planner.skill_name(package, s), from_registry: s["registry"].present? } },
        tools: package.section("tools").map { |t| { name: t["platform"] || t["name"], platform: t["platform"].present?, image: t["docker_image"] } },
        mcp_servers: package.section("mcp_servers").map { |m| { name: m.dig("custom", "name") || m.dig("connector", "name") || m["internal"], connector: m["connector"].present?, built_in: m["internal"].present? } },
        assets: package.section("assets").pluck("name"),
        workflows: package.section("workflows").map { |w| { name: w["name"], steps: w["steps"].pluck("name") } },
        triggers: package.section("triggers").map { |t| t.slice("kind", "workflow", "column", "cron") },
        variables: package.variables.pluck("name")
      }
    end

    def plan(plan)
      {
        template: { slug: plan.catalog_template.slug, version: plan.catalog_template.version,
                    commit_sha: plan.catalog_template.commit_sha },
        target: plan.target_kind, project_id: plan.project&.id, project_name: plan.project&.name || plan.project_name,
        company_id: plan.company.id, digest: plan.digest, resolved: plan.resolved?,
        items: plan.items.map(&:to_h), conflicts: plan.conflicts.map(&:to_h),
        board_action: plan.board_action, warnings: plan.warnings,
        checklist: plan.checklist.map { |item| item.slice(:kind, :ref, :detail) }
      }
    end

    def setup_item(item)
      { id: item.id, kind: item.kind, ref: item.ref, status: item.status, detail: item.detail.except("attach_to"),
        label: setup_label(item) }
    end

    def setup_label(item)
      detail = item.detail
      case item.kind
      when "secret" then "Add the secret #{detail['name']}"
      when "integration" then "Connect #{detail['provider'].to_s.titleize}"
      when "repository" then "Attach a repository (#{detail['key']})"
      when "oauth" then "Sign in to #{detail['name']}"
      when "probe" then "Could not reach #{detail['name']}"
      when "trigger" then "Activate the #{detail['kind']} trigger of #{detail['workflow_name'] || detail['workflow']}"
      when "board" then "Board changes were skipped"
      else item.ref
      end
    end
  end
end
