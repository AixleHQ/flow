# frozen_string_literal: true
module InternalTools
  class YoutrackSearchIssues < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Search Issues"; description "Search issues in the connected YouTrack project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: [], properties: { query: { type: "string" }, top: { type: "integer" }, skip: { type: "integer" } } })
    end
    def execute
      with_youtrack do |client, integration|
        query = "project: {#{integration.settings['project_short_name']}} #{params[:query]}".strip
        rows = client.get("/api/issues", query: query, "$top": [params[:top].to_i.nonzero? || 50, 100].min,
          "$skip": params[:skip].to_i, fields: "id,idReadable,summary,project(id,name,shortName)")
        rows.each { |issue| client.assert_selected_project!(issue) }
        json_success(rows)
      end
    end
  end
end
