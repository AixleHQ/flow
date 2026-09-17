# frozen_string_literal: true
module InternalTools
  class YoutrackManageIssueTags < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Manage Issue Tags"; description "Add or remove tags on an issue in the connected project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: ["issue_id"], properties: { issue_id: { type: "string" }, add: { type: "array", items: { type: "string" } }, remove: { type: "array", items: { type: "string" } } } })
    end
    def execute
      with_youtrack do |c, _|
        c.checked_issue(params[:issue_id], fields: "id,project(id)")
        id = CGI.escapeURIComponent(params[:issue_id].to_s)
        Array(params[:add]).each { |tag| c.post("/api/issues/#{id}/tags", name: tag) }
        Array(params[:remove]).each { |tag| c.post("/api/issues/#{id}/tags/#{CGI.escapeURIComponent(tag.to_s)}", { remove: true }) }
        json_success({ added: Array(params[:add]), removed: Array(params[:remove]) })
      end
    end
  end
end
