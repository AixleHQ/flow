# frozen_string_literal: true

module Tools
  # The personal (token-authenticated) MCP server as its users see it: the name
  # their client registers it under, the URL they point at, and which of the
  # registry's `audience :user` tools it actually serves them.
  module PersonalMCP
    # The name a client registers this server under. It prefixes every tool the
    # agent sees (`mcp__flow__list_projects`), so it is user-visible surface,
    # not an internal id — keep it in step with the product name.
    NAME = "flow"

    class << self
      # `MCP_PUBLIC_SERVER_URL` wins; otherwise the app's own public host.
      # Built here rather than as a settings.yml default because the
      # per-environment `protocol` (https everywhere except development/test)
      # is only known once the environment file has been merged — the literal
      # `http://` that default used to hardcode handed every deployed user a
      # URL their MCP client refuses.
      def public_url
        Settings.mcp.public_server_url.presence || "#{Settings.protocol}://#{Settings.domain}/mcp"
      end

      # The tool definitions this user's server serves, ordered by name.
      #
      # `mcp_enabled_tools` is nil for "everything" — including tools shipped
      # after the user last touched the picker. An array narrows it, and names
      # that have since left the registry are dropped rather than kept as dead
      # entries.
      def definitions_for(user)
        defs = Registry.for_audience(:user).sort_by(&:name)
        return defs if user.mcp_enabled_tools.nil?

        allowed = user.mcp_enabled_tools.to_set
        defs.select { |d| allowed.include?(d.name) }
      end

      # The picker's shape: the same groups the `tool_catalog` prompt uses, so
      # what a user switches off in the UI is described to them the same way the
      # agent has it described. Unlike the prompt, a tool appears exactly once —
      # a multi-tagged tool (`trigger_task_workflow` is both :board and
      # :workflows) lands in its first group, because two checkboxes for one
      # tool would disagree with each other. A tool whose tags have no group
      # still shows up, under "Other" — never silently unselectable.
      def catalog_groups
        remaining = Registry.for_audience(:user).sort_by(&:name)

        groups = PersonalMCPGuides::CATALOG_GROUPS.filter_map do |group|
          tools, remaining = remaining.partition { |d| d.tags.include?(group[:tag]) }
          next if tools.empty?

          { tag: group[:tag].to_s, title: group[:title], blurb: group[:blurb], tools: tools.map { |d| tool_entry(d) } }
        end

        return groups if remaining.empty?

        groups << { tag: "other", title: "Other", blurb: nil, tools: remaining.map { |d| tool_entry(d) } }
      end

      # Persists a selection. `names` nil (or covering the whole registry) is
      # stored as NULL so tools added later stay switched on — a materialized
      # "everything" list would silently freeze the server at today's surface.
      def update_selection!(user, names)
        known = Registry.for_audience(:user).map(&:name)
        selected = names.nil? ? nil : Array(names).map(&:to_s).uniq & known
        selected = nil if selected && selected.sort == known.sort

        user.update!(mcp_enabled_tools: selected)
      end

      private

      # The wire name, not the display name: `list_projects` is what the user
      # sees in their agent, so it is what they recognize in the picker.
      def tool_entry(defn)
        {
          name: defn.name,
          description: defn.description,
          read_only: defn.annotations.fetch("readOnlyHint", false)
        }
      end
    end
  end
end
