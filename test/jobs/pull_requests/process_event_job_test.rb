# frozen_string_literal: true

require "test_helper"

class PullRequests::ProcessEventJobTest < ActiveJob::TestCase
  test "an event survives the queue and is published for the repositories it names" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    repository = create(:repository, scope: project, full_name: "acme/api",
                                     integration: create(:integration, :github, :active, company: company, project: project))
    create(:trigger_binding, project: project, workflow: create(:workflow, scope: project), created_by: user,
                             event_type: "pull_request.review.submitted")
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))
    event = PullRequests::Event.build(kind: :review_submitted, number: 12, actor: { id: "7", name: "ada" },
                                      verdict: "approved", revision: "r-9")

    PullRequests::ProcessEventJob.perform_later(repository_ids: [ repository.id ], event: event.to_job)
    perform_enqueued_jobs(only: PullRequests::ProcessEventJob)

    published = TriggerEvent.sole
    assert_equal [ "pull_request.review.submitted", "approved", "ada" ],
                 [ published.event_type, published.data.dig("review", "verdict"), published.data.dig("actor", "name") ]
  end
end
