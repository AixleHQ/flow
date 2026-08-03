# frozen_string_literal: true

module InternalTools
  class MetaSearchSkills < Base
    tool do
      display_name "Meta Search Skills"
      description "Search the skills.sh registry for available agent skills."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[query],
        properties: {
          query: {
            type: "string",
            description: "Search query (e.g. mantine, react, testing)"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      query = params[:query].to_s.strip
      return error("query is required") if query.blank?
      return error("query must be at least 2 characters") if query.length < Skills::RegistryClient::MIN_QUERY_LENGTH

      results = SkillsRegistryService.search(query)

      success({
        query: query,
        results_count: results.size,
        skills: results.map { |s| { id: s[:id], slug: s[:slug], name: s[:name], source: s[:source], installs: s[:installs] } }
      }.to_json)
    end
  end
end
