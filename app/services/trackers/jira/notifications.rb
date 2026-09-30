# frozen_string_literal: true

module Trackers
  module Jira
    # A Jira webhook payload reduced to Trackers::Notification. Admin and app
    # webhooks share the payload shape; only how they authenticate differs.
    module Notifications
      FIELDS = { "status" => "status", "assignee" => "assignee" }.freeze

      module_function

      # `projects` are the connection's Jira projects; an issue in any other
      # project yields nothing.
      def parse(payload, projects:)
        issue = payload["issue"].to_h
        scope_id = scope_for(issue, projects)
        return [] if issue["id"].blank? || scope_id.nil?

        base = { scope_id: scope_id, issue_id: issue["id"].to_s, actor: actor(payload["user"]),
                 occurred_at: occurred_at(payload["timestamp"]) }
        case payload["webhookEvent"]
        when "jira:issue_created"
          [ Notification.build(kind: :issue_created, revision: "created", **base) ]
        when "jira:issue_updated"
          changes = changes(payload.dig("changelog", "items"))
          changes.empty? ? [] : [ Notification.build(kind: :issue_updated, changes: changes, revision: payload.dig("changelog", "id")&.to_s, **base) ]
        when "comment_created"
          comment = payload["comment"].to_h
          return [] if comment["id"].blank?

          [ Notification.build(kind: :comment_created, comment_id: comment["id"].to_s, comment_text: comment["body"].to_s,
                               **base.merge(actor: actor(comment["author"] || payload["user"]))) ]
        else []
        end
      end

      # By project id; a comment event whose issue carries no project falls back
      # to the key's prefix.
      def scope_for(issue, projects)
        id = issue.dig("fields", "project", "id").to_s
        prefix = issue["key"].to_s.split("-").first.to_s
        project = projects.find { |p| p["id"].to_s == id } if id.present?
        project ||= projects.find { |p| p["key"].to_s.casecmp?(prefix) } if id.blank? && prefix.present?
        project && project["id"].to_s
      end

      def changes(items)
        Array(items).filter_map do |item|
          field = FIELDS[item["fieldId"].presence || item["field"]]
          next unless field

          { field: field, from: item["fromString"], to: item["toString"], from_id: item["from"], to_id: item["to"] }.compact
        end
      end

      def actor(user)
        return {} unless user.is_a?(Hash)

        { id: user["accountId"], name: user["displayName"] }.compact
      end

      def occurred_at(timestamp)
        Time.zone.at(timestamp.to_i / 1000.0).iso8601(3) if timestamp.present?
      end
    end
  end
end
