# frozen_string_literal: true

module PullRequests
  module AzureDevops
    # Azure DevOps Service Hook deliveries → PullRequests::Event. The delivery
    # authenticated with its subscription's password, and the subscription is
    # created with `resourceDetailsToSend: all`, so the comment and its pull
    # request are in the payload.
    #
    # A comment's id counts within its thread, so the thread is part of its id.
    #
    # A vote comes as `git.pullrequest.updated`, which also fires on a push, a
    # reviewer added or a status change and never says which, nor whose vote
    # changed. So each update is answered with the vote threads published around
    # it (AzureDevops::PullRequestService#vote_updates); a vote seen twice — by
    # its own update and by a push right after — publishes once, deduplicated on
    # its thread.
    module Events
      COMMENT_EVENT = "ms.vss-code.git-pullrequest-comment-event"
      UPDATE_EVENT = "git.pullrequest.updated"
      THREAD_ID = %r{/threads/(\d+)}
      # 5 is "approve with suggestions", -5 "waiting for author"; 0 is a vote
      # taken back, which is no review.
      VOTE_VERDICTS = { 10 => "approved", 5 => "approved", -5 => "changes_requested", -10 => "changes_requested" }.freeze
      VOTE_WINDOW = 5.minutes

      module_function

      def parse(event_type, resource)
        return unless event_type.to_s == COMMENT_EVENT

        comment = resource["comment"].to_h
        return if comment["commentType"].to_s == "system" || comment["isDeleted"]

        pr = resource["pullRequest"].to_h
        thread = thread_id(comment)
        Event.build(kind: :comment_created, number: pr["pullRequestId"], title: pr["title"], url: web_url(pr),
                    source_branch: branch(pr["sourceRefName"]), target_branch: branch(pr["targetRefName"]),
                    author: pr.dig("createdBy", "displayName"),
                    actor: { id: comment.dig("author", "id"), name: comment.dig("author", "displayName") },
                    body: comment["content"], comment_id: [ thread, comment["id"] ].compact.join("/").presence,
                    reply_to: (comment["parentCommentId"] if comment["parentCommentId"].to_i.positive?)&.to_s,
                    occurred_at: comment["publishedDate"])
      end

      # `resource` is the pull request of an update delivery, `updates` its
      # vote threads, `at` when Azure says the update happened.
      def votes(resource, updates, at:)
        at = parse_time(at) || Time.current
        updates.filter_map do |update|
          verdict = VOTE_VERDICTS[update[:vote]]
          published = parse_time(update[:published_at])
          next if verdict.nil? || published.nil? || !published.between?(at - VOTE_WINDOW, at + 1.minute)

          Event.build(kind: :review_submitted, number: resource["pullRequestId"], title: resource["title"],
                      url: web_url(resource), source_branch: branch(resource["sourceRefName"]),
                      target_branch: branch(resource["targetRefName"]), author: resource.dig("createdBy", "displayName"),
                      actor: voter(resource, update[:voter]), verdict: verdict, revision: update[:thread_id].to_s,
                      occurred_at: update[:published_at])
        end
      end

      def repository_id(resource)
        resource.dig("pullRequest", "repository", "id").presence
      end

      # A voter Azure named only by display name gets its id from the reviewers.
      def voter(resource, voter)
        voter = voter.to_h.symbolize_keys
        return voter if voter[:id].present?

        reviewer = Array(resource["reviewers"]).find { |r| r["displayName"].present? && r["displayName"] == voter[:name] }
        voter.merge(id: reviewer&.dig("id")).compact
      end

      def parse_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def thread_id(comment)
        links = comment["_links"].to_h
        href = links.dig("threads", "href") || links.dig("self", "href")
        href.to_s[THREAD_ID, 1]
      end

      def web_url(pr)
        base = pr.dig("repository", "webUrl").presence
        base && "#{base}/pullrequest/#{pr['pullRequestId']}"
      end

      def branch(ref)
        ref.to_s.delete_prefix("refs/heads/").presence
      end
    end
  end
end
