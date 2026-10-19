# frozen_string_literal: true

module Trackers
  module Gitlab
    # A GitLab project hook's Issue Hook or Note Hook, reduced to
    # Trackers::Notification (docs/design/gitlab-tracker.md §5). A column change
    # is read off the label lists and the state before and after; GitLab names
    # the labels it changed in `changes.labels` and the closing in `action`.
    #
    # Confidential issues and internal notes yield nothing: their hooks are not
    # subscribed, and a note marked internal is dropped if one arrives anyway.
    module Notifications
      STATES = { "close" => %w[opened closed], "reopen" => %w[closed opened] }.freeze

      module_function

      # `lists` are the board's label lists, in board order.
      def parse(payload, scope_id:, lists:)
        case payload["object_kind"]
        when "issue", "work_item" then issue(payload, scope_id, lists)
        when "note" then note(payload, scope_id)
        else []
        end
      end

      def issue(payload, scope_id, lists)
        attrs = payload["object_attributes"].to_h
        return [] unless attrs["project_id"].to_s == scope_id && attrs["iid"].present? && !attrs["confidential"]

        id = "#{scope_id}:#{attrs['iid']}"
        common = { scope_id: scope_id, issue_id: id, actor: actor(payload["user"]), occurred_at: attrs["updated_at"] }
        return [ Notification.build(kind: :issue_created, revision: "created", **common) ] if attrs["action"] == "open"

        changes = [ status_change(payload, attrs, lists), assignee_change(payload) ].compact
        return [] if changes.empty?

        [ Notification.build(kind: :issue_updated, changes: changes, revision: attrs["updated_at"], **common) ]
      end

      def note(payload, scope_id)
        attrs = payload["object_attributes"].to_h
        issue = payload["issue"].to_h
        return [] unless attrs["noteable_type"] == "Issue" && issue["project_id"].to_s == scope_id && issue["iid"].present?
        return [] if attrs["internal"] || attrs["confidential"] || issue["confidential"] || attrs["system"]

        [ Notification.build(kind: :comment_created, scope_id: scope_id, issue_id: "#{scope_id}:#{issue['iid']}",
                             comment_id: attrs["id"].to_s, comment_text: attrs["note"].to_s, actor: actor(payload["user"]),
                             occurred_at: attrs["created_at"]) ]
      end

      def status_change(payload, attrs, lists)
        labels = payload.dig("changes", "labels")
        current_labels = names(labels ? labels["current"] : payload["labels"])
        previous_labels = labels ? names(labels["previous"]) : current_labels
        from_state, to_state = STATES.fetch(attrs["action"].to_s, [ attrs["state"], attrs["state"] ])
        from = column(previous_labels, from_state, lists)
        to = column(current_labels, to_state, lists)
        { field: "status", from: from, to: to } unless from == to
      end

      def assignee_change(payload)
        change = payload.dig("changes", "assignees")
        return unless change

        previous = names(change["previous"], key: "username")
        current = names(change["current"], key: "username")
        added = current - previous
        { field: "assignee", from: previous.first, to: added.first } if added.any?
      end

      def column(labels, state, lists)
        return Provider::CLOSED if state == "closed"

        lists.find { |label| labels.include?(label) } || Provider::OPEN
      end

      def names(list, key: "title")
        Array(list).filter_map { |item| item.is_a?(Hash) ? (item[key] || item["name"]) : item.to_s.presence }
      end

      def actor(user)
        user = user.to_h
        { id: user["id"]&.to_s, name: user["username"], login: user["username"] }.compact
      end
    end
  end
end
