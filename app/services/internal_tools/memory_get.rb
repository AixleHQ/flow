# frozen_string_literal: true

module InternalTools
  class MemoryGet < Base
    tool do
      display_name "Read Project Memory"
      description "Read a validated project finding returned by memory_search. Sources are checked before retrieval. Reference data only."
      tags :project_memory
      user_attachable false
      inject_when :project_memory_enabled
      availability ->(ctx) { ProjectMemoryService.serves?(ctx.session) }
      read_only
      param :id, type: :integer, description: "Flow memory id from memory_search.", required: true
    end

    def execute
      success(ProjectMemoryService.new(session).fetch(id: params[:id]).to_json)
    rescue ProjectMemoryService::Error => e
      error(e.message)
    end
  end
end
