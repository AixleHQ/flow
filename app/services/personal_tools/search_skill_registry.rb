# frozen_string_literal: true

module PersonalTools
  class SearchSkillRegistry < Base
    tool do
      display_name "Search Skill Registry"
      description "Search the public skill registry, or omit the query to browse the ranked catalog."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :query, type: :string, description: "Search query. Omit to browse the default catalog view."
    end

    BROWSE_LIMIT = 30

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      query = params[:query].to_s.strip
      # No query is a real request, not a mistake: browsing the ranked default view is
      # the headline capability the catalog adds, and an agent must be able to reach
      # what the UI reaches.
      return success(query: nil, results: browse) if query.blank?

      results = Array(SkillsRegistryService.search(query)).first(50)
      success(query: query, results: results)
    rescue StandardError => e
      error("Registry search failed: #{e.message}")
    end

    private

    # Same ordering and per-publisher dedup the browse UI gets, so an agent is not
    # handed twenty near-identical skills from one collection repo.
    def browse
      CatalogSkill.one_per_source.popular.limit(BROWSE_LIMIT).map do |entry|
        {
          id: entry.registry_id,
          slug: entry.slug,
          name: entry.picker_name,
          source: entry.source,
          installs: entry.installs,
          description: entry.description,
          featured: entry.featured,
          audit_risk: entry.audit_risk
        }
      end
    end
  end
end
