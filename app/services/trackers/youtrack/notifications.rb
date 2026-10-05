# frozen_string_literal: true

module Trackers
  module Youtrack
    # A Webhook Triggers app payload (github.com/JetBrains/youtrack-apps,
    # packages/webhook-triggers-app) reduced to Trackers::Notification.
    #
    # A delivery is for the YouTrack project whose subscription it reached:
    # the app holds one token per project. The project the payload names (by
    # short name, which a rename changes) is not checked here; the issue is
    # re-read, and one in another project is refused then. People come without
    # their id, so the actor is only a hint until the provider confirms it.
    #
    # Comment text is left out: it is read from YouTrack, and a delivery keeps
    # identifiers and change hints only.
    module Notifications
      module_function

      # `project` is the subscription's entry of the connection's youtrack_projects.
      def parse(payload, project:)
        return [] unless payload.is_a?(Hash) && project

        issue_id = payload["id"].to_s
        return [] if issue_id.blank?

        base = { scope_id: project["id"].to_s, issue_id: issue_id, occurred_at: payload["timestamp"].presence }
        case payload["event"]
        when "issueCreated"
          [ Notification.build(kind: :issue_created, actor: actor(payload["reporter"]), revision: "created", **base) ]
        when "issueUpdated"
          changes = changes(payload["changedFields"], project)
          return [] if changes.empty?

          [ Notification.build(kind: :issue_updated, changes: changes, actor: actor(payload["updatedBy"]),
                               revision: payload["updated"].to_s.presence, **base) ]
        when "commentAdded"
          Array(payload["comments"]).filter_map do |comment|
            next unless comment.is_a?(Hash) && comment["id"].present?

            Notification.build(kind: :comment_created, comment_id: comment["id"].to_s, actor: actor(comment["author"]), **base)
          end
        else []
        end
      end

      # The project's state field is the status; its assignee field the
      # assignee, one change per person added to a multi-person field.
      def changes(fields, project)
        status = project["status_field"].presence || "State"
        assignee = project["assignee_field"].presence || "Assignee"
        Array(fields).flat_map do |field|
          next [] unless field.is_a?(Hash)

          case field["name"]
          when status then [ { field: "status", from: name_of(field["oldValue"]), to: name_of(field["value"]) }.compact ]
          when assignee then assignments(field["oldValue"], field["value"])
          else []
          end
        end.select { |change| change[:to].present? }
      end

      def assignments(old_value, value)
        before = logins(old_value)
        (logins(value) - before).map { |login| { field: "assignee", from: before.first, to: login }.compact }
      end

      def name_of(value)
        value.is_a?(Hash) ? (value["name"].presence || value["presentation"]) : value.presence
      end

      def logins(value)
        Array(value.is_a?(Hash) ? [ value ] : value).filter_map { |v| v["login"].presence if v.is_a?(Hash) }
      end

      def actor(user)
        return {} unless user.is_a?(Hash)

        { login: user["login"], name: user["fullName"].presence || user["login"] }.compact
      end
    end
  end
end
