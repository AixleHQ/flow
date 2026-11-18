# frozen_string_literal: true

require "test_helper"

class PullRequests::AzureDevops::EventsTest < ActiveSupport::TestCase
  REPOSITORY_ID = "3c4d5e6f-0000-4000-8000-000000000001"

  def resource(comment = {})
    {
      "comment" => {
        "id" => 2, "parentCommentId" => 1, "content" => "Rename this", "commentType" => "text",
        "publishedDate" => "2026-11-17T10:00:00Z",
        "author" => { "id" => "a1b2", "displayName" => "Ada Lovelace" },
        "_links" => { "self" => { "href" => "https://dev.azure.com/contoso/_apis/git/repositories/r/pullRequests/5/threads/14/comments/2" } }
      }.merge(comment),
      "pullRequest" => {
        "pullRequestId" => 5, "title" => "Add retries", "sourceRefName" => "refs/heads/retries",
        "targetRefName" => "refs/heads/main", "createdBy" => { "displayName" => "Aixle" },
        "repository" => { "id" => REPOSITORY_ID, "webUrl" => "https://dev.azure.com/contoso/Platform/_git/api" }
      }
    }
  end

  def parse(resource) = PullRequests::AzureDevops::Events.parse("ms.vss-code.git-pullrequest-comment-event", resource)

  test "a comment's id is qualified by its thread, since ids count within a thread" do
    event = parse(resource)

    assert_equal [ :comment_created, 5, "14/2", "1", "retries", "main" ],
                 [ event.kind, event.number, event.comment_id, event.reply_to, event.source_branch, event.target_branch ]
    assert_equal "https://dev.azure.com/contoso/Platform/_git/api/pullrequest/5", event.url
    assert_equal({ id: "a1b2", name: "Ada Lovelace" }, event.actor)
    assert_equal REPOSITORY_ID, PullRequests::AzureDevops::Events.repository_id(resource)
  end

  def pull_request
    {
      "pullRequestId" => 5, "title" => "Add retries", "sourceRefName" => "refs/heads/retries",
      "targetRefName" => "refs/heads/main", "createdBy" => { "displayName" => "Aixle" },
      "repository" => { "id" => REPOSITORY_ID, "webUrl" => "https://dev.azure.com/contoso/Platform/_git/api" },
      "reviewers" => [ { "id" => "g1", "displayName" => "Grace", "vote" => -10 } ]
    }
  end

  def vote(thread_id, value, voter, published_at = "2026-11-18T10:00:00Z")
    { thread_id: thread_id, vote: value, voter: voter, published_at: published_at }
  end

  test "an update answers with the votes cast around it, each a review by its voter" do
    updates = [
      vote(1, 10, { id: "a1", name: "Ada" }, "2026-11-18T09:00:00Z"),
      vote(2, 5, { id: "a1", name: "Ada" }),
      vote(3, -10, { name: "Grace" }),
      vote(4, 0, { id: "a1", name: "Ada" })
    ]

    events = PullRequests::AzureDevops::Events.votes(pull_request, updates, at: "2026-11-18T10:00:01Z")

    assert_equal [ [ "approved", { id: "a1", name: "Ada" }, "2" ], [ "changes_requested", { name: "Grace", id: "g1" }, "3" ] ],
                 events.map { |e| [ e.verdict, e.actor, e.revision ] }
    assert_equal [ :review_submitted, 5, "retries", "https://dev.azure.com/contoso/Platform/_git/api/pullrequest/5" ],
                 [ events.first.kind, events.first.number, events.first.source_branch, events.first.url ]
  end

  test "system comments, like a vote recorded in the thread, are not comments" do
    assert_nil parse(resource("commentType" => "system"))
    assert_nil PullRequests::AzureDevops::Events.parse("git.pullrequest.updated", resource)
  end
end
