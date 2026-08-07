# frozen_string_literal: true

module PersonalTools
  # The catalog a workflow author picks a step's `tool_ids` from.
  #
  # Deliberately NOT chained with `.ui_visible`: that scope means "custom tools
  # the UI lets you manage" (`db_source`), which is mutually exclusive with the
  # platform half of `visible_for_project` — chaining the two stripped every
  # platform tool back out and answered `[]` for any project without custom
  # tools. `visible_for_project` is the same set the UI pickers offer, so it is
  # what an MCP client should see too.
  class ListProjectTools < Base
    # High enough that a real project is never clipped; when it is, the payload
    # says so instead of pretending the list is complete.
    LIMIT = 200

    tool do
      display_name "List Project Tools"
      description "List the tools available in a project — attachable platform tools plus the " \
                  "project's own custom tools — with description, tags and integration " \
                  "requirement, so a step's tool_ids can be chosen rather than guessed."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::ToolsPolicy, project: project)

      # One row past the cap: enough to tell "exactly full" from "clipped".
      found = Tool.visible_for_project(project).order(:source, :name).limit(LIMIT + 1).to_a
      truncated = found.size > LIMIT
      rows = found.first(LIMIT).map { |t| serialize(t) }

      payload = { project_id: project.id, tools_count: rows.size, tools: rows, truncated: truncated }
      payload[:note] = "Listing capped at #{LIMIT} tools; more are available." if truncated
      success(payload)
    end

    private

    # Registry-first, like the session MCP server: for a platform tool the
    # in-code definition is authoritative, so a shadow row that has not been
    # reconciled since the last deploy can never serve stale metadata.
    def serialize(tool)
      defn = tool.definition
      { id: tool.id,
        name: tool.name,
        display_name: defn&.display_name.presence || tool.display_name,
        description: (defn&.description.presence || tool.description)&.truncate(200),
        source: tool.source,
        tags: (defn&.tags || tool.tags).map(&:to_s),
        requires_integration: (defn&.requires_integration || tool.requires_integration)&.to_s,
        enabled: tool.enabled }
    end
  end
end
