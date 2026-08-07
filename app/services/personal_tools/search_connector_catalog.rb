# frozen_string_literal: true

module PersonalTools
  # The MCP connector catalog, as the MCP servers page browses it. Two different
  # jobs, so two different scopes — same split as the web controller:
  # search goes over the whole mirror (the upstream registry API can only match
  # server-name substrings, so "issue tracker" finds nothing there), while the
  # default view is the curated set, because the open registry is mostly long tail.
  class SearchConnectorCatalog < Base
    tool do
      display_name "Search Connector Catalog"
      description "Search the public MCP connector catalog, or omit the query to browse the curated set. " \
                  "Returns catalog entries, not installs — read one with get_connector, then " \
                  "install_connector. Everything outside the curated set is reachable by search only."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :query, type: :string, description: "Search query. Omit to browse the curated set."
    end

    LIMIT = 30

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::MCPServersPolicy, project: project)

      query = params[:query].to_s.strip
      success(query: query.presence, results: rows(query))
    end

    private

    def rows(query)
      entries(query).map do |connector|
        { name: connector.name, title: connector.picker_name,
          description: connector.description&.truncate(200),
          version: connector.version, status: connector.status.to_s,
          # The registry verified this publisher owns the domain, rather than
          # merely holding a GitHub account — the one provenance signal the
          # catalog actually has.
          vendor_published: connector.vendor_published?,
          installable: connector.installable? }
      end
    end

    def entries(query)
      scope = Connector.discoverable
      return scope.search(query).limit(LIMIT) if query.present?

      scope.where(featured: true).popular.limit(LIMIT)
    end
  end
end
