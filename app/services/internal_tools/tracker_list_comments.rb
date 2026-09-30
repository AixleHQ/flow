# frozen_string_literal: true

module InternalTools
  class TrackerListComments < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: List Comments"
      description "List an issue's comments, oldest first where the tracker allows. Paginated: pass `next_cursor` " \
                  "back as `cursor`. Returns JSON: {tracker, comments: [{id, author, body, created_at}], has_more, " \
                  "next_cursor}."
      tags :tracker
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :limit, type: :integer, description: "Page size, default 50, at most 100."
      param :cursor, type: :string, description: "`next_cursor` from the previous page."
    end

    def execute
      tracker_guard do
        tracker = resolve_tracker!
        page = tracker.tracker_provider.list_comments(tracker.external_scope_id, params[:issue],
                                                      cursor: params[:cursor], limit: params[:limit])
        respond({ tracker: tracker.handle, comments: page.items, has_more: page.has_more?, next_cursor: page.next_cursor }.compact)
      end
    end
  end
end
