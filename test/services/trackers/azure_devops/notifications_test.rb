# frozen_string_literal: true

require "test_helper"

module Trackers
  module AzureDevops
    # Resources shaped like Azure's documented Service Hook samples
    # (learn.microsoft.com/azure/devops/service-hooks/events).
    class NotificationsTest < ActiveSupport::TestCase
      SCOPE = "00aa00aa-bb11-cc22-dd33-44ee44ee44ee"

      test "an update names the work item by workItemId — its own id is the update's number" do
        resource = {
          "id" => 5, "workItemId" => 308, "rev" => 2,
          "revisedBy" => { "id" => "11bb", "displayName" => "Chuck Reinhart" },
          "fields" => {
            "System.BoardColumn" => { "oldValue" => "New", "newValue" => "Ready for AI" },
            "System.State" => { "oldValue" => "New", "newValue" => "Approved" },
            "System.AssignedTo" => { "oldValue" => nil, "newValue" => "Ada Lovelace <ada@example.com>" },
            "System.Reason" => { "oldValue" => "New", "newValue" => "Approved" },
            "System.Title" => "Sample task"
          }
        }

        notification = Notifications.parse("workitem.updated", resource, scope_id: SCOPE)

        assert_equal [ :issue_updated, "308", SCOPE, 2 ],
                     [ notification.kind, notification.issue_id, notification.scope_id, notification.revision ]
        assert_equal [ { field: "board_column", from: "New", to: "Ready for AI" },
                       { field: "state", from: "New", to: "Approved" },
                       { field: "assignee", from: nil, to: "Ada Lovelace <ada@example.com>" } ], notification.changes
        assert_equal({ id: "11bb", name: "Chuck Reinhart" }, notification.actor)
      end

      test "an update with no workItemId is dropped rather than read as work item 5" do
        assert_nil Notifications.parse("workitem.updated", { "id" => 5, "fields" => {} }, scope_id: SCOPE)
      end

      test "a created work item carries itself; identity fields may be objects" do
        resource = { "id" => 308, "rev" => 1, "fields" => {
          "System.State" => "New",
          "System.ChangedBy" => { "id" => "22cc", "displayName" => "Grace Hopper" }
        } }

        notification = Notifications.parse("workitem.created", resource, scope_id: SCOPE)

        assert_equal [ :issue_created, "308", [] ], [ notification.kind, notification.issue_id, notification.changes ]
        assert_equal({ id: "22cc", name: "Grace Hopper" }, notification.actor)
      end

      test "a comment's text is System.History, wherever the resource puts it" do
        in_fields = Notifications.parse("workitem.commented",
                                        { "id" => 308, "rev" => 3, "fields" => { "System.History" => "In fields" } },
                                        scope_id: SCOPE)
        top_level = Notifications.parse("workitem.commented",
                                        { "id" => 308, "rev" => 3, "fields" => {}, "System.History" => "Top level" },
                                        scope_id: SCOPE)

        assert_equal [ :comment_created, "In fields" ], [ in_fields.kind, in_fields.comment_text ]
        assert_equal "Top level", top_level.comment_text
      end

      test "an event type it does not know is not a notification" do
        assert_nil Notifications.parse("workitem.deleted", { "id" => 308 }, scope_id: SCOPE)
      end
    end
  end
end
