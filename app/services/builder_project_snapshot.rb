# frozen_string_literal: true

# What the Aixle Builder knows about its project before its first tool call:
# every id it is likely to wire, so it reuses what exists instead of guessing or
# creating duplicates. Config item values never appear — only keys and kinds.
class BuilderProjectSnapshot
  LIMIT = 30

  def self.render(project, user:)
    new(project, user).render
  end

  def initialize(project, user)
    @project = project
    @user = user
  end

  def render
    [
      "## Project: #{@project.name} (id #{@project.id})",
      @project.description.presence,
      block("Agent runtimes you can run", runtimes),
      block("Integrations", integrations, empty: "none connected — steps get no GitHub/GitLab/Slack/Azure DevOps access"),
      block("Board columns", board_columns, empty: "no board yet — `setup_board` creates one"),
      block("Workflows", workflows, empty: "none yet"),
      block("Agents", agents, empty: "none yet"),
      block("Repositories", repositories, empty: "none attached"),
      block("MCP servers", mcp_servers, empty: "none"),
      block("Skills", skills, empty: "none installed"),
      block("Config items (keys only)", config_items, empty: "none"),
      block("Assets", assets, empty: "none")
    ].compact.join("\n\n")
  end

  private

  def block(title, lines, empty: nil)
    return "### #{title}\n#{empty}" if lines.empty? && empty
    return nil if lines.empty?

    more = lines.size > LIMIT ? [ "- … #{lines.size - LIMIT} more — use the list tools" ] : []
    "### #{title}\n#{(lines.first(LIMIT) + more).join("\n")}"
  end

  def runtimes
    membership = @user.company_memberships.active.find_by(company_id: @project.company_id)
    return [] unless membership

    default = membership.default_agent_runtime
    membership.configured_agents.uniq.map { |r| "- #{r}#{' (default)' if r == default}" }
  end

  def integrations
    Integration.visible_for_project(@project).order(:provider).map do |i|
      "- #{i.provider}: #{i.name} (id #{i.id}, #{i.status})"
    end
  end

  def board_columns
    board = @project.board
    return [] unless board

    board.board_columns.includes(column_workflow_binding: :workflow).order(:position).map do |c|
      binding = c.column_workflow_binding
      trigger = binding ? " → runs \"#{binding.workflow.name}\" (#{binding.trigger_mode})" : ""
      "- #{c.name} (id #{c.id})#{trigger}"
    end
  end

  def workflows
    Workflow.visible_for_project(@project).includes(:steps, :trigger_bindings).order(:name).map do |w|
      steps = w.steps.count { |s| s.deleted_at.nil? }
      triggers = w.trigger_bindings.map(&:event_type).uniq
      "- #{w.name} (id #{w.id}, #{steps} #{'step'.pluralize(steps)}" \
        "#{", triggers: #{triggers.join(', ')}" if triggers.any?})"
    end
  end

  def agents
    Agent.visible_for_project(@project).order(:name).map { |a| "- #{a.title.presence || a.name} (id #{a.id})" }
  end

  def repositories
    Repository.visible_for_project(@project).order(:full_name).map do |r|
      "- #{r.full_name} (id #{r.id}, branch #{r.source_branch.presence || 'default'})"
    end
  end

  def mcp_servers
    MCPServer.for_project(@project).order(:name).map do |s|
      "- #{s.name} (id #{s.id}#{', disabled' unless s.enabled?}#{", #{s.auth_type} auth" if s.auth_type.present? && s.auth_type != 'none'})"
    end
  end

  def skills
    Skill.visible_for_project(@project).order(:name).map { |s| "- #{s.name} (id #{s.id})" }
  end

  def config_items
    ConfigItem.visible_for_project(@project).order(:name).map { |c| "- #{c.name} (id #{c.id}, #{c.item_type})" }
  end

  def assets
    Asset.visible_for_project(@project).order(created_at: :desc).map { |a| "- #{a.name} (id #{a.id})" }
  end
end
