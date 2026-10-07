# frozen_string_literal: true

module Trackers
  module Youtrack
    # An Aixle Flow app event (youtrack-app/README.md, "Events") reduced to
    # Trackers::Notification.
    #
    # An event is for the YouTrack project whose subscription it reached. The
    # project the payload names (by short name, which a rename changes) is not
    # checked here; the issue is re-read, and one in another project is refused
    # then. Everything else is a hint until the provider confirms it. A comment
    # carries its id when the app could read one, and its author and creation
    # time either way, by which it is found otherwise.
    module Notifications
      module_function

      # `project` is the subscription's entry of the connection's youtrack_projects.
      def parse(payload, project:)
        return [] unless payload.is_a?(Hash) && project && payload["version"].to_i >= 1

        issue_id = payload["issue"].to_s
        return [] if issue_id.blank?

        base = { scope_id: project["id"].to_s, issue_id: issue_id, occurred_at: time(payload["at"]) }
        case payload["event"]
        when "issue_created"
          [ Notification.build(kind: :issue_created, actor: actor(payload["actor"]), revision: "created", **base) ]
        when "issue_updated"
          changes = changes(payload["changes"])
          return [] if changes.empty?

          [ Notification.build(kind: :issue_updated, changes: changes, actor: actor(payload["actor"]),
                               revision: payload["at"].to_s.presence, **base) ]
        when "comment_added"
          Array(payload["comments"]).filter_map do |comment|
            next unless comment.is_a?(Hash)

            Notification.build(kind: :comment_created, comment_id: comment["id"].to_s.presence, actor: actor(comment["author"]),
                               **base, occurred_at: time(comment["created"]) || base[:occurred_at])
          end
        else []
        end
      end

      # One assignee change per person added to a multi-person field.
      def changes(changes)
        return [] unless changes.is_a?(Hash)

        status = changes["status"]
        assignee = changes["assignee"]
        result = []
        result << { field: "status", from: status["from"].presence, to: status["to"].presence }.compact if status.is_a?(Hash)
        if assignee.is_a?(Hash)
          before = Array(assignee["from"]).compact_blank
          (Array(assignee["to"]).compact_blank - before).each do |login|
            result << { field: "assignee", from: before.first, to: login }.compact
          end
        end
        result.select { |change| change[:to].present? }
      end

      def actor(login)
        login.is_a?(String) && login.present? ? { login: login } : {}
      end

      # Epoch milliseconds, as YouTrack keeps time.
      def time(millis)
        Time.zone.at(millis.to_i / 1000.0).iso8601(3) if millis.is_a?(Numeric) || millis.to_s.match?(/\A\d+\z/)
      end
    end
  end
end
