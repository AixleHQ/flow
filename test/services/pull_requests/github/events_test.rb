# frozen_string_literal: true

require "test_helper"

class PullRequests::Github::EventsTest < ActiveSupport::TestCase
  PULL_REQUEST = {
    "number" => 12, "title" => "Add retries", "html_url" => "https://github.com/acme/api/pull/12",
    "head" => { "ref" => "retries" }, "base" => { "ref" => "main" }, "user" => { "login" => "aixle-flow[bot]" }
  }.freeze

  def parse(event, payload) = PullRequests::Github::Events.parse(event, payload)

  test "a submitted review becomes a review with its verdict, body and reviewer" do
    event = parse("pull_request_review", {
      "action" => "submitted", "pull_request" => PULL_REQUEST,
      "review" => { "id" => 501, "state" => "CHANGES_REQUESTED", "body" => "Handle the timeout",
                    "user" => { "id" => 7, "login" => "ada" }, "submitted_at" => "2026-11-17T10:00:00Z" }
    })

    assert_equal [ :review_submitted, 12, "changes_requested", "Handle the timeout", "501" ],
                 [ event.kind, event.number, event.verdict, event.body, event.revision ]
    assert_equal [ "retries", "main", "aixle-flow[bot]" ], [ event.source_branch, event.target_branch, event.author ]
    assert_equal({ id: "7", name: "ada" }, event.actor)
  end

  test "an edited or dismissed review is not a new review" do
    assert_nil parse("pull_request_review", { "action" => "edited", "pull_request" => PULL_REQUEST, "review" => { "state" => "approved" } })
    assert_nil parse("pull_request_review", { "action" => "submitted", "pull_request" => PULL_REQUEST, "review" => { "state" => "dismissed" } })
  end

  test "an inline review comment says where in the diff it was left and what it answers" do
    event = parse("pull_request_review_comment", {
      "action" => "created", "pull_request" => PULL_REQUEST,
      "comment" => { "id" => 9001, "body" => "Rename this", "path" => "lib/client.rb", "line" => nil, "original_line" => 40,
                     "in_reply_to_id" => 9000, "user" => { "id" => 7, "login" => "ada" } }
    })

    assert_equal [ :comment_created, "9001", "lib/client.rb", 40, "9000" ],
                 [ event.kind, event.comment_id, event.file, event.line, event.reply_to ]
  end

  test "a conversation comment counts only on a pull request, not on a plain issue" do
    payload = { "action" => "created", "comment" => { "id" => 3, "body" => "@aixle-flow fix it", "user" => { "id" => 7, "login" => "ada" } },
                "issue" => { "number" => 12, "title" => "Add retries", "html_url" => "https://github.com/acme/api/pull/12",
                             "pull_request" => { "html_url" => "https://github.com/acme/api/pull/12" } } }

    event = parse("issue_comment", payload)
    assert_equal [ 12, "3", "https://github.com/acme/api/pull/12" ], [ event.number, event.comment_id, event.url ]

    assert_nil parse("issue_comment", payload.merge("issue" => payload["issue"].except("pull_request")))
  end
end
