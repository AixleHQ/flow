# frozen_string_literal: true

module Trackers
  module Github
    # GitHub App webhooks → Trackers::Notification.
    #
    # `projects_v2_item` names the project its item is on. `issues` and
    # `issue_comment` name only the repository, so they become one notification
    # per tracked project, and the pipeline drops the ones whose board does not
    # hold the issue. Draft issues never count: they are not issues.
    module Notifications
      TRACKED = {
        "projects_v2_item" => %w[created converted edited],
        "issues" => %w[assigned],
        "issue_comment" => %w[created]
      }.freeze
      CONTENT_TYPES = %w[Issue PullRequest].freeze

      module_function

      def tracked?(event, action)
        TRACKED.fetch(event.to_s, []).include?(action.to_s)
      end

      # `projects` are the connection's chosen projects (settings.github_projects).
      def parse(event, payload, projects:)
        return [] unless tracked?(event, payload["action"])

        case event.to_s
        when "projects_v2_item" then item(payload, projects)
        when "issues" then assigned(payload, projects)
        when "issue_comment" then commented(payload, projects)
        else []
        end
      end

      def item(payload, projects)
        item = payload["projects_v2_item"].to_h
        project = projects.find { |p| p["id"] == item["project_node_id"] }
        return [] unless project && CONTENT_TYPES.include?(item["content_type"]) && item["content_node_id"].present?

        base = { scope_id: project["id"], issue_id: item["content_node_id"], actor: actor(payload["sender"]),
                 occurred_at: item["updated_at"] }
        return [ Notification.build(kind: :issue_created, revision: item["node_id"], **base) ] unless payload["action"] == "edited"

        change = payload.dig("changes", "field_value").to_h
        status_field = project["status_field"].presence || Provider::DEFAULT_STATUS_FIELD
        return [] unless change["field_type"] == "single_select" && change["field_name"].to_s.casecmp?(status_field)

        [ Notification.build(kind: :issue_updated, changes: [ { field: "status", from: change.dig("from", "name"), to: change.dig("to", "name") } ],
                             revision: [ item["node_id"], change.dig("to", "id"), item["updated_at"] ].join(":"), **base) ]
      end

      def assigned(payload, projects)
        issue = payload["issue"].to_h
        login = payload.dig("assignee", "login")
        return [] if issue["node_id"].blank? || login.blank?

        projects.map do |project|
          Notification.build(kind: :issue_updated, scope_id: project["id"], issue_id: issue["node_id"],
                             changes: [ { field: "assignee", from: nil, to: login } ], actor: actor(payload["sender"]),
                             revision: "assigned:#{login}:#{issue['updated_at']}", occurred_at: issue["updated_at"])
        end
      end

      def commented(payload, projects)
        issue = payload["issue"].to_h
        comment = payload["comment"].to_h
        return [] if issue["node_id"].blank? || comment["node_id"].blank?

        projects.map do |project|
          Notification.build(kind: :comment_created, scope_id: project["id"], issue_id: issue["node_id"],
                             comment_id: comment["node_id"], comment_text: comment["body"].to_s,
                             actor: actor(comment["user"] || payload["sender"]), occurred_at: comment["created_at"])
        end
      end

      def actor(user)
        return {} unless user.is_a?(Hash)

        { id: user["id"]&.to_s, name: user["login"] }.compact
      end
    end
  end
end
