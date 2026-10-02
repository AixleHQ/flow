# frozen_string_literal: true

module Trackers
  module Linear
    # A Linear webhook payload reduced to Trackers::Notification. An update
    # names what changed in `updatedFrom`, with the previous values by id.
    module Notifications
      module_function

      # `teams` are the connection's Linear teams; an issue of any other team yields nothing.
      def parse(payload, teams:)
        data = payload["data"].to_h
        case [ payload["type"], payload["action"] ]
        when %w[Issue create] then issue_created(payload, data, teams)
        when %w[Issue update] then issue_updated(payload, data, teams)
        when %w[Comment create] then comment_created(payload, data, teams)
        else []
        end
      end

      def issue_created(payload, data, teams)
        team = covered(data["teamId"], teams)
        return [] if team.nil? || data["id"].blank?

        [ Notification.build(kind: :issue_created, scope_id: team, issue_id: data["id"], actor: actor(payload["actor"]),
                             revision: "created", occurred_at: payload["createdAt"]) ]
      end

      def issue_updated(payload, data, teams)
        team = covered(data["teamId"], teams)
        from = payload["updatedFrom"].to_h
        return [] if team.nil? || data["id"].blank?

        changes = []
        if from.key?("stateId")
          changes << { field: "status", from_id: from["stateId"], to_id: data["stateId"], to: data.dig("state", "name") }.compact
        end
        if from.key?("assigneeId") && data["assigneeId"].present?
          changes << { field: "assignee", from_id: from["assigneeId"], to_id: data["assigneeId"],
                       to: data.dig("assignee", "name") }.compact
        end
        return [] if changes.empty?

        [ Notification.build(kind: :issue_updated, scope_id: team, issue_id: data["id"], changes: changes,
                             actor: actor(payload["actor"]), revision: data["updatedAt"], occurred_at: payload["createdAt"]) ]
      end

      def comment_created(payload, data, teams)
        issue_id = data["issueId"].presence || data.dig("issue", "id")
        team = covered(data.dig("issue", "teamId"), teams)
        return [] if team.nil? || issue_id.blank? || data["id"].blank?

        [ Notification.build(kind: :comment_created, scope_id: team, issue_id: issue_id, comment_id: data["id"],
                             comment_text: data["body"].to_s, actor: actor(payload["actor"] || data["user"]),
                             occurred_at: data["createdAt"]) ]
      end

      def covered(team_id, teams)
        team_id.to_s if team_id.present? && teams.any? { |t| t["id"].to_s == team_id.to_s }
      end

      def actor(actor)
        return {} unless actor.is_a?(Hash)

        { id: actor["id"], name: actor["name"] }.compact
      end
    end
  end
end
