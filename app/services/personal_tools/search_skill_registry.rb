# frozen_string_literal: true

module PersonalTools
  class SearchSkillRegistry < Base
    tool do
      display_name "Search Skill Registry"
      description "Search the public skill registry to find skills to install into a project."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :query, type: :string, description: "Search query.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)
      return error("query is required") if params[:query].blank?

      results = Array(SkillsRegistryService.search(params[:query])).first(50)
      success(query: params[:query], results: results)
    rescue StandardError => e
      error("Registry search failed: #{e.message}")
    end
  end
end
