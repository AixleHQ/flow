# frozen_string_literal: true

module InternalTools
  class TrackerSearchIssues < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Search Issues"
      description "Search issues in a tracker's project with structured filters (all optional, combined with AND). " \
                  "Paginated: pass `next_cursor` back as `cursor`. Returns JSON: {tracker, issues: [{id, key, url, " \
                  "title, type, status, assignees, labels}], has_more, next_cursor}."
      tags :tracker
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :text, type: :string, description: "Words the title contains."
      param :status, type: :string, description: "Exact status name."
      param :type, type: :string, description: "Exact issue type name."
      param :assignee, type: :string, description: "Assignee, as the tracker names users."
      param :labels, type: :array, items: { "type" => "string" }, description: "Labels the issue carries."
      param :ids, type: :array, items: { "type" => "string" }, description: "Only these issue ids."
      param :open_only, type: :boolean, description: "Leave out finished and removed issues."
      param :native_query, type: :string, description: "A query in the tracker's own language, where it has one."
      param :limit, type: :integer, description: "Page size, default 50, at most 100."
      param :cursor, type: :string, description: "`next_cursor` from the previous page."
    end

    FILTERS = %i[text status type assignee labels ids open_only native_query].freeze

    def execute
      tracker_guard do
        tracker = resolve_tracker!(ref: nil)
        filter = params.slice(*FILTERS.map(&:to_s)).symbolize_keys.compact_blank
        page = tracker.tracker_provider.search_issues(tracker.external_scope_id, filter,
                                                      cursor: params[:cursor], limit: params[:limit])
        respond({ tracker: tracker.handle, issues: page.items, has_more: page.has_more?, next_cursor: page.next_cursor }.compact)
      end
    end
  end
end
