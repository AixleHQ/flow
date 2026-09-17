# frozen_string_literal: true

module InternalTools
  class YoutrackGetIssueComments < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Get Issue Comments"; description "List comments on an issue in the connected project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: [ "issue_id" ], properties: { issue_id: { type: "string" }, top: { type: "integer" }, skip: { type: "integer" } } })
    end
    def execute
      with_youtrack do |c, _|
        c.checked_issue(params[:issue_id], fields: "id,project(id)")
        json_success(c.get("/api/issues/#{CGI.escapeURIComponent(params[:issue_id].to_s)}/comments", "$top": params[:top] || 50,
          "$skip": params[:skip] || 0, fields: "id,text,created,updated,author(id,login,name)"))
      end
    end
  end
end
