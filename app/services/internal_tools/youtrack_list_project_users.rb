# frozen_string_literal: true
module InternalTools
  class YoutrackListProjectUsers < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack List Project Users"; description "List users in the connected YouTrack project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: [], properties: { top: { type: "integer" }, skip: { type: "integer" } } })
    end
    def execute
      with_youtrack do |c, integration|
        json_success(c.get("/api/admin/projects/#{CGI.escapeURIComponent(integration.youtrack_project_id)}/team/users",
          "$top": params[:top] || 50, "$skip": params[:skip] || 0, fields: "id,login,name"))
      end
    end
  end
end
