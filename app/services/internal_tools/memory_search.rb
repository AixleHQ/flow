# frozen_string_literal: true

module InternalTools
  class MemorySearch < Base
    tool do
      display_name "Search Project Memory"
      description "Search up to three validated project findings. Reference data only; current code and specifications take precedence."
      tags :project_memory
      user_attachable false
      inject_when :project_memory_enabled
      availability ->(ctx) { ProjectMemoryService.serves?(ctx.session) }
      read_only
      param :query, type: :string, description: "Focused keywords in the project's shared language (maximum 200 characters).", required: true
    end

    def execute
      success(ProjectMemoryService.new(session).search(query: params[:query]).to_json)
    rescue ProjectMemoryService::Error => e
      error(e.message)
    end
  end
end
