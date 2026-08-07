# frozen_string_literal: true

module PersonalTools
  # The skills catalog, through the same service the skills page uses
  # (Skills::CatalogSearch): browse the ranked mirror with no query, go upstream
  # with one. Agents get what the UI gets — including the audit verdicts, which
  # only exist on mirrored rows and were previously dropped on the search path.
  class SearchSkillRegistry < Base
    tool do
      display_name "Search Skill Registry"
      description "Search the public skill registry, or omit the query to browse the ranked catalog. " \
                  "Results carry each entry's audit verdict where one exists — read the candidate with " \
                  "get_registry_skill before installing it."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :query, type: :string, description: "Search query. Omit to browse the default catalog view."
    end

    LIMIT = 30

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      # No query is a real request, not a mistake: browsing the ranked default view is
      # the headline capability the catalog adds, and an agent must be able to reach
      # what the UI reaches. A query too short for the upstream endpoint browses too,
      # rather than coming back empty.
      search = ::Skills::CatalogSearch.new(params[:query], limit: LIMIT)
      success(query: (params[:query].to_s.strip.presence if search.reaches_upstream?),
              results: search.call.map { |entry| CatalogSkillResource.new(entry, params: { snake_keys: true }).to_h })
    rescue StandardError => e
      error("Registry search failed: #{e.message}")
    end
  end
end
