# frozen_string_literal: true

module PullRequests
  module Bitbucket
    # Forge product events of the Aixle Flow app → PullRequests::Event. The
    # invocation token was verified (Webhooks::BitbucketForgeController), so the
    # payload is Bitbucket's. A comment event names the comment only; its text
    # and place in the diff are read through the API by the caller.
    #
    # `selfGenerated` marks what the app itself did, which is how a bot account
    # with no identity of its own is told apart from a person.
    module Events
      COMMENT_CREATED = "avi:bitbucket:created:pullrequest-comment"
      REVIEWER_STATUS = "avi:bitbucket:updated:pullrequest-reviewer-status"
      EVENT_TYPES = [ COMMENT_CREATED, REVIEWER_STATUS ].freeze
      VERDICTS = { "approved" => "approved", "changes_requested" => "changes_requested" }.freeze
      WEB_HOST = "https://bitbucket.org"

      module_function

      def comment?(payload) = payload["eventType"] == COMMENT_CREATED

      def repository_uuid(payload)
        ::Bitbucket::Identifiers.uuid(payload.dig("repository", "uuid"))
      end

      def pull_request_id(payload) = payload.dig("pullrequest", "id")

      def comment_id(payload) = payload.dig("comment", "id")

      # `comment` is the API's answer for a comment event (Bitbucket::Api#comment).
      def parse(payload, full_name:, comment: nil)
        case payload["eventType"]
        when COMMENT_CREATED then comment_event(payload, full_name, comment)
        when REVIEWER_STATUS then review_event(payload, full_name)
        end
      end

      def comment_event(payload, full_name, comment)
        return if comment.nil? || comment[:deleted]

        Event.build(kind: :comment_created, **pull_request(payload, full_name), own: payload["selfGenerated"] == true,
                    actor: { id: comment[:author_uuid], name: comment[:author] }, body: comment[:body],
                    comment_id: comment[:id]&.to_s, file: comment[:path], line: comment[:line],
                    reply_to: comment[:parent_id]&.to_s, occurred_at: comment[:created_on] || payload["timestamp"])
      end

      # The reviewer whose status changed is the one who acted.
      def review_event(payload, full_name)
        actor = ::Bitbucket::Identifiers.uuid(payload.dig("actor", "uuid"))
        reviewer = reviewers(payload).find { |entry| ::Bitbucket::Identifiers.uuid(entry.dig("user", "uuid")) == actor }
        verdict = VERDICTS[reviewer&.dig("status").to_s]
        return if actor.nil? || verdict.nil?

        Event.build(kind: :review_submitted, **pull_request(payload, full_name), own: payload["selfGenerated"] == true,
                    actor: { id: actor }, verdict: verdict,
                    revision: [ verdict, reviewer["timestamp"] || payload["timestamp"] ].join(":"),
                    occurred_at: reviewer["timestamp"] || payload["timestamp"])
      end

      def reviewers(payload)
        list = payload["reviewers"]
        list = list["value"] if list.is_a?(Hash)
        Array(list).select { |entry| entry.is_a?(Hash) }
      end

      def pull_request(payload, full_name)
        pr = payload["pullrequest"].to_h
        title = pr["title"].is_a?(Hash) ? pr.dig("title", "value") : pr["title"]
        { number: pr["id"], title: title, url: "#{WEB_HOST}/#{full_name}/pull-requests/#{pr['id']}",
          source_branch: branch(pr["source"]), target_branch: branch(pr["destination"]),
          author: pr.dig("author", "displayName") }
      end

      def branch(side)
        branch = side.to_h["branch"]
        branch.is_a?(Hash) ? branch["name"] : branch
      end
    end
  end
end
