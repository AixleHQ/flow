# frozen_string_literal: true

require "test_helper"

class PullRequests::Bitbucket::EventsTest < ActiveSupport::TestCase
  ADA = "{7a1b2c3d-0000-4000-8000-0000000000ad}"
  BOB = "{7a1b2c3d-0000-4000-8000-0000000000b0}"

  def payload(event_type, **extra)
    { "eventType" => event_type, "timestamp" => "2026-11-17T10:00:00Z", "selfGenerated" => false,
      "actor" => { "type" => "user", "uuid" => ADA },
      "repository" => { "uuid" => "{5b6c7d8e-0000-4000-8000-000000000001}" },
      "pullrequest" => { "id" => 8, "title" => { "truncated" => false, "value" => "Add retries" },
                         "source" => { "branch" => "retries" }, "destination" => { "branch" => { "name" => "main" } },
                         "author" => { "displayName" => "Aixle Flow" } } }.merge(extra)
  end

  def parse(payload, comment: nil) = PullRequests::Bitbucket::Events.parse(payload, full_name: "acme/api", comment: comment)

  test "the acting reviewer's new status is the review's verdict" do
    event = parse(payload(PullRequests::Bitbucket::Events::REVIEWER_STATUS, "reviewers" => {
      "truncated" => false,
      "value" => [ { "user" => { "uuid" => BOB }, "status" => "approved", "timestamp" => "t0" },
                   { "user" => { "uuid" => ADA }, "status" => "changes_requested", "timestamp" => "t1" } ]
    }))

    assert_equal [ :review_submitted, 8, "changes_requested", "Add retries" ], [ event.kind, event.number, event.verdict, event.title ]
    assert_equal [ "retries", "main", "https://bitbucket.org/acme/api/pull-requests/8" ],
                 [ event.source_branch, event.target_branch, event.url ]
    assert_equal ADA, event.actor[:id]
  end

  test "a reviewer status that is no verdict, or someone else's, is no review" do
    withdrawn = { "value" => [ { "user" => { "uuid" => ADA }, "status" => nil } ] }
    others = { "value" => [ { "user" => { "uuid" => BOB }, "status" => "approved" } ] }

    assert_nil parse(payload(PullRequests::Bitbucket::Events::REVIEWER_STATUS, "reviewers" => withdrawn))
    assert_nil parse(payload(PullRequests::Bitbucket::Events::REVIEWER_STATUS, "reviewers" => others))
  end

  test "a comment event takes the comment the API returned, and marks the app's own" do
    comment = { id: 301, parent_id: 300, author: "Ada", author_uuid: ADA, body: "Rename this", path: "lib/client.rb",
                line: 40, created_on: "2026-11-17T10:00:00Z", deleted: false }

    event = parse(payload(PullRequests::Bitbucket::Events::COMMENT_CREATED, "selfGenerated" => true), comment: comment)

    assert_equal [ :comment_created, "301", "300", "lib/client.rb", 40, true ],
                 [ event.kind, event.comment_id, event.reply_to, event.file, event.line, event.own ]
    assert_nil parse(payload(PullRequests::Bitbucket::Events::COMMENT_CREATED), comment: nil)
  end
end
