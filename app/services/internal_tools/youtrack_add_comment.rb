# frozen_string_literal: true

module InternalTools
  class YoutrackAddComment < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Add Comment"; description "Add a comment to an issue in the connected project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: %w[issue_id text], properties: { issue_id: { type: "string" }, text: { type: "string" } } })
    end
    def execute
      with_youtrack do |c, _|
        c.checked_issue(params[:issue_id], fields: "id,project(id)")
        json_success(c.post("/api/issues/#{CGI.escapeURIComponent(params[:issue_id].to_s)}/comments?fields=id,text,author(id,login)", text: params[:text]))
      end
    end
  end
end
