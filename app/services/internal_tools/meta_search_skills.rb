# frozen_string_literal: true

module InternalTools
  class MetaSearchSkills < Base
    include MetaToolHelpers

    def execute
      query = params[:query]
      return error("query is required") if query.blank?

      results = SkillsRegistryService.search(query)

      success({
        query: query,
        results_count: results.size,
        skills: results.map { |s| { id: s[:id], name: s[:name], source: s[:source], installs: s[:installs] } }
      }.to_json)
    end
  end
end
