# frozen_string_literal: true

module InternalTools
  class MemoryCapture < Base
    tool do
      display_name "Propose Project Memory"
      description "Propose a concise reusable finding for project-owner review. Always pending; never save secrets, transcripts or specification copies."
      tags :project_memory
      user_attachable false
      inject_when :project_memory_enabled
      availability ->(ctx) { ProjectMemoryService.serves?(ctx.session) }
      destructive false
      param :title, type: :string, description: "Brief finding title (maximum 120 characters).", required: true
      param :content, type: :string, description: "Finding, reason and supporting evidence (maximum 2000 characters).", required: true
      param :topic_key, type: :string, description: "Stable lowercase family/topic key (maximum 100 characters).", required: true
      param :sources, type: :string, description: "JSON array of up to three {repository_id, path, revision} sources from attached repositories; revision is the file last-commit SHA. Use [] for a proposal awaiting sources.", required: true
    end

    def execute
      sources = JSON.parse(params[:sources].to_s)
      success(ProjectMemoryService.new(session).capture(
        title: params[:title], content: params[:content], topic_key: params[:topic_key], sources: sources
      ).to_json)
    rescue JSON::ParserError
      error("Project memory: invalid sources JSON")
    rescue ProjectMemoryService::Error => e
      error(e.message)
    end
  end
end
