# frozen_string_literal: true

module ContextBuilders
  # A run started by a tracker event: which tracker and issue started it, and
  # that the tracker_* tools default to them.
  class TrackerContext < Base
    EVENT_DESCRIPTIONS = {
      "tracker.issue.created" => "was created",
      "tracker.issue.status_changed" => "changed status",
      "tracker.issue.assigned" => "was assigned",
      "tracker.comment.created" => "got a comment"
    }.freeze

    def applicable?
      tracker.present?
    end

    def build
      [ section(tag: "tracker-trigger", priority: :critical, content: content, position_hint: :top) ]
    end

    private

    def tracker
      @tracker ||= workflow_run&.shared_context.to_h["tracker"]
    end

    def content
      issue = tracker["issue"].to_h
      lines = [
        "## Triggering issue",
        "",
        "This run was started because #{issue_label(issue)} in the `#{tracker['handle']}` tracker " \
        "#{EVENT_DESCRIPTIONS.fetch(tracker['event_type'], 'changed')}#{change_suffix}. The `tracker_*` tools act on " \
        "this tracker unless you pass another `tracker`; read the issue in full with `tracker_get_issue`."
      ]
      lines += [ "", "Comment:", "", "> #{tracker.dig('comment', 'text').to_s.gsub("\n", "\n> ")}" ] if tracker.dig("comment", "text").present?
      lines += [ "", code_linking(issue) ] if code_linking?(issue)
      lines.join("\n")
    end

    # Jira (and the hosts' own issue links) attach branches, commits and pull
    # requests to an issue by finding its key in their names — no integration
    # of ours is involved, so the names are the whole mechanism.
    def code_linking(issue)
      key = (issue["key"].presence || issue["id"]).to_s
      branch = key.gsub(/[^A-Za-z0-9._-]+/, "-").delete_prefix("-")
      "When you change code for this issue, start branch names with `#{branch}` (`#{branch}-short-description`) " \
        "and begin pull-request titles and commit messages with `#{key}` (`#{key}: …`), so the issue links to the work."
    end

    def code_linking?(issue)
      (issue["key"].presence || issue["id"]).present? &&
        session.repositories.joins(:integration).where(integrations: { provider: Repository::CODE_HOST_PROVIDERS }).exists?
    end

    def issue_label(issue)
      label = [ issue["key"] || issue["id"], issue["title"] ].compact_blank.join(" ")
      issue["url"].present? ? "issue [#{label}](#{issue['url']})" : "issue #{label}"
    end

    def change_suffix
      change = tracker["change"].to_h
      return "" if change.blank?

      from = change["from"].is_a?(Hash) ? change.dig("from", "name") : change["from"]
      to = change["to"].is_a?(Hash) ? change.dig("to", "name") : change["to"]
      from.present? ? " (#{from} → #{to})" : " (to #{to})"
    end
  end
end
