# frozen_string_literal: true

module InternalTools
  class YoutrackGetIssue < Base
    include Concerns::YoutrackContext
    tool do
      display_name "YouTrack Get Issue"; description "Read one issue from the connected YouTrack project."
      tags :youtrack; inject_when :workflow_step_session; requires_integration :youtrack
      input_schema({ type: "object", required: [ "issue_id" ], properties: { issue_id: { type: "string" } } })
    end
    def execute = with_youtrack { |c, _| json_success(c.checked_issue(params[:issue_id])) }
  end
end
