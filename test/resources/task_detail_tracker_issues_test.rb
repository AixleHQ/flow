# frozen_string_literal: true

require "test_helper"

class TaskDetailTrackerIssuesTest < ActiveSupport::TestCase
  test "the task detail names the tracker issues the task is linked to" do
    project = create(:project, company: (company = create(:company)), owner: create(:user, company: company))
    board = create(:board, project: project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    task.external_resources.create!(kind: ExternalResource::TRACKER_ISSUE, provider: "azure_devops",
                                    instance: "https://dev.azure.com/acme", external_id: "308",
                                    data: { "key" => "308", "url" => "https://dev.azure.com/acme/p/_workitems/edit/308" })

    issues = TaskDetailResource.new(task).to_h["trackerIssues"]

    assert_equal [ { "provider" => "azure_devops", "key" => "308", "url" => "https://dev.azure.com/acme/p/_workitems/edit/308" } ],
                 issues.map(&:stringify_keys)
  end
end
