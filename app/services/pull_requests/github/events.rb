# frozen_string_literal: true

module PullRequests
  module Github
    # GitHub App deliveries → PullRequests::Event. Webhooks::GithubController has
    # verified the App's signature, so the payload is GitHub's own account of
    # the change. A comment in a pull request's conversation arrives as
    # `issue_comment`, on an issue that names its pull request.
    module Events
      TRACKED = {
        "pull_request_review" => %w[submitted],
        "pull_request_review_comment" => %w[created],
        "issue_comment" => %w[created]
      }.freeze
      VERDICTS = %w[approved changes_requested commented].freeze

      module_function

      def tracked?(event, payload)
        return false unless TRACKED.fetch(event.to_s, []).include?(payload["action"].to_s)

        event.to_s != "issue_comment" || payload.dig("issue", "pull_request").present?
      end

      def parse(event, payload)
        return unless tracked?(event, payload)

        case event.to_s
        when "pull_request_review" then review(payload)
        when "pull_request_review_comment" then review_comment(payload)
        else conversation_comment(payload)
        end
      end

      def review(payload)
        review = payload["review"].to_h
        verdict = review["state"].to_s.downcase
        return unless VERDICTS.include?(verdict)

        Event.build(kind: :review_submitted, **pull_request(payload["pull_request"].to_h),
                    actor: actor(review["user"] || payload["sender"]), verdict: verdict, body: review["body"],
                    revision: review["id"]&.to_s, occurred_at: review["submitted_at"])
      end

      def review_comment(payload)
        comment = payload["comment"].to_h
        Event.build(kind: :comment_created, **pull_request(payload["pull_request"].to_h), actor: actor(comment["user"]),
                    body: comment["body"], comment_id: comment["id"]&.to_s, file: comment["path"],
                    line: comment["line"] || comment["original_line"], reply_to: comment["in_reply_to_id"]&.to_s,
                    occurred_at: comment["created_at"])
      end

      # The issue side of a pull request names no branches.
      def conversation_comment(payload)
        issue = payload["issue"].to_h
        comment = payload["comment"].to_h
        Event.build(kind: :comment_created, number: issue["number"], title: issue["title"],
                    url: issue.dig("pull_request", "html_url") || issue["html_url"], author: issue.dig("user", "login"),
                    actor: actor(comment["user"]), body: comment["body"], comment_id: comment["id"]&.to_s,
                    occurred_at: comment["created_at"])
      end

      def pull_request(pr)
        { number: pr["number"], title: pr["title"], url: pr["html_url"], source_branch: pr.dig("head", "ref"),
          target_branch: pr.dig("base", "ref"), author: pr.dig("user", "login") }
      end

      def actor(user)
        user = user.to_h
        { id: user["id"]&.to_s, name: user["login"] }
      end
    end
  end
end
