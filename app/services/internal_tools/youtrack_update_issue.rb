# frozen_string_literal: true

module InternalTools
  class YoutrackUpdateIssue < Base
    include Concerns::YoutrackContext
    ALLOWED_CHANGES = %w[summary description customFields].freeze
    tool do
      display_name "YouTrack Update Issue"; description "Update summary, description, or custom fields on an issue in the connected project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: [ "issue_id", "changes" ], properties: { issue_id: { type: "string" }, changes: { type: "object" } } })
    end
    def execute
      with_youtrack do |c, _|
        changes = params[:changes].to_h.stringify_keys
        return error("Only summary, description, and customFields can be updated") unless (changes.keys - ALLOWED_CHANGES).empty?
        return error("customFields must be a list") if changes.key?("customFields") && !changes["customFields"].is_a?(Array)
        c.checked_issue(params[:issue_id], fields: "id,project(id)")
        result = c.post("/api/issues/#{CGI.escapeURIComponent(params[:issue_id].to_s)}?fields=id,idReadable,summary,project(id)", changes)
        json_success(c.assert_selected_project!(result))
      end
    end
  end
end
