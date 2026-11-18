# frozen_string_literal: true

require "test_helper"

class PullRequests::Gitlab::EventsTest < ActiveSupport::TestCase
  MERGE_REQUEST = {
    "iid" => 4, "title" => "Add retries", "url" => "https://gitlab.com/group/app/-/merge_requests/4",
    "source_branch" => "retries", "target_branch" => "main"
  }.freeze
  USER = { "id" => 31, "username" => "ada", "name" => "Ada Lovelace" }.freeze

  def parse(hook, payload) = PullRequests::Gitlab::Events.parse(hook, payload)

  def note(attributes = {})
    { "object_kind" => "note", "user" => USER, "merge_request" => MERGE_REQUEST,
      "object_attributes" => { "id" => 77, "note" => "Rename this", "noteable_type" => "MergeRequest", "system" => false,
                               "action" => "create", "created_at" => "2026-11-17 10:00:00 UTC",
                               "position" => { "new_path" => "lib/client.rb", "new_line" => 40 } }.merge(attributes) }
  end

  def merge_request_hook(action, changes: {})
    { "object_kind" => "merge_request", "user" => USER, "changes" => changes,
      "object_attributes" => MERGE_REQUEST.merge("action" => action, "updated_at" => "2026-11-17 10:05:00 UTC") }
  end

  test "a diff note on a merge request is a comment at its place in the diff" do
    event = parse("Note Hook", note)

    assert_equal [ :comment_created, 4, "77", "lib/client.rb", 40, "retries" ],
                 [ event.kind, event.number, event.comment_id, event.file, event.line, event.source_branch ]
    assert_equal({ id: "31", name: "ada" }, event.actor)
  end

  test "system notes, edits and notes on anything but a merge request are not comments" do
    assert_nil parse("Note Hook", note("system" => true))
    assert_nil parse("Note Hook", note("action" => "update"))
    assert_nil parse("Note Hook", note("noteable_type" => "Issue"))
  end

  test "one person's approval is an approved review; the merge request becoming fully approved is not" do
    assert_equal "approved", parse("Merge Request Hook", merge_request_hook("approval")).verdict
    assert_nil parse("Merge Request Hook", merge_request_hook("approved"))
  end

  test "a submitted review shows as the reviewer's own state changing" do
    changes = { "reviewers" => { "previous" => [ { "id" => 31, "state" => "review_started" } ],
                                 "current" => [ { "id" => 31, "state" => "requested_changes" } ] } }

    assert_equal "changes_requested", parse("Merge Request Hook", merge_request_hook("update", changes: changes)).verdict
  end

  test "an update that leaves the actor's review state alone is no review" do
    someone_else = { "reviewers" => { "previous" => [], "current" => [ { "id" => 99, "state" => "requested_changes" } ] } }

    assert_nil parse("Merge Request Hook", merge_request_hook("update"))
    assert_nil parse("Merge Request Hook", merge_request_hook("update", changes: someone_else))
  end
end
