# frozen_string_literal: true
module InternalTools
  class YoutrackUpdateIssue < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Update Issue"; description "Update summary, description, or custom fields on an issue in the connected project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: ["issue_id", "changes"], properties: { issue_id: { type: "string" }, changes: { type: "object" } } })
    end
    def execute
      with_youtrack do |c, _|
        c.checked_issue(params[:issue_id], fields: "id,project(id)")
        json_success(c.post("/api/issues/#{CGI.escapeURIComponent(params[:issue_id].to_s)}?fields=id,idReadable,summary,project(id)", params[:changes].to_h))
      end
    end
  end
end
