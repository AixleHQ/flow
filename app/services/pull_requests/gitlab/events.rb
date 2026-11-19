# frozen_string_literal: true

module PullRequests
  module Gitlab
    # GitLab project-hook deliveries → PullRequests::Event. The hook carries the
    # repository's own secret (Webhooks::GitlabController), so the payload is
    # GitLab's own account of the change.
    #
    # An approval is `action: approval` — `approved` means every required
    # approval is in, which is not one person's review. A submitted review
    # (GitLab 19.3+) is `action: update` with the reviewer's state changing.
    module Events
      NOTE_HOOK = "Note Hook"
      MERGE_REQUEST_HOOK = "Merge Request Hook"
      HOOKS = [ NOTE_HOOK, MERGE_REQUEST_HOOK ].freeze
      REVIEW_STATES = { "requested_changes" => "changes_requested", "reviewed" => "commented" }.freeze

      module_function

      def parse(hook, payload)
        case hook.to_s
        when NOTE_HOOK then note(payload)
        when MERGE_REQUEST_HOOK then review(payload)
        end
      end

      def note(payload)
        note = payload["object_attributes"].to_h
        return unless note["noteable_type"] == "MergeRequest" && !note["system"] && note["action"].to_s.in?([ "", "create" ])

        position = note["position"].to_h
        Event.build(kind: :comment_created, **merge_request(payload["merge_request"].to_h), actor: actor(payload["user"]),
                    body: note["note"], comment_id: note["id"]&.to_s, file: position["new_path"] || position["old_path"],
                    line: position["new_line"] || position["old_line"], occurred_at: note["created_at"])
      end

      def review(payload)
        attributes = payload["object_attributes"].to_h
        user = payload["user"].to_h
        verdict = case attributes["action"].to_s
        when "approval" then "approved"
        when "update" then submitted_review(payload, user)
        end
        return unless verdict

        Event.build(kind: :review_submitted, **merge_request(attributes), actor: actor(user), verdict: verdict,
                    revision: [ attributes["action"], attributes["updated_at"] ].join(":"),
                    occurred_at: attributes["updated_at"])
      end

      def submitted_review(payload, user)
        change = payload.dig("changes", "reviewers").to_h
        current = Array(change["current"]).find { |reviewer| reviewer["id"].to_s == user["id"].to_s }
        previous = Array(change["previous"]).find { |reviewer| reviewer["id"].to_s == user["id"].to_s }
        return if current.nil? || current["state"] == previous&.dig("state")

        REVIEW_STATES[current["state"].to_s]
      end

      def merge_request(attributes)
        { number: attributes["iid"], title: attributes["title"], url: attributes["url"],
          source_branch: attributes["source_branch"], target_branch: attributes["target_branch"] }
      end

      def actor(user)
        user = user.to_h
        { id: user["id"]&.to_s, name: user["username"].presence || user["name"] }
      end
    end
  end
end
