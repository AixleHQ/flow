# frozen_string_literal: true

require "test_helper"

# The job's whole reason for existing: a Service Hook payload is a notification,
# not state. `git.pullrequest.merged` fires for a merge that FAILED on a conflict
# exactly as it does for one that landed, so believing the payload would mark CI
# green for a merge that never happened.
#
# These keep WebMock rather than FakeAzureDevops on purpose. What is under test
# is that the job goes BACK to Azure and prefers that answer over the delivered
# one — asserted against a real HTTP round trip whose body disagrees with the
# payload. Faking the adapter here would assert that the fake re-reads, not that
# the job does.
class ResolveAzureDevopsEventJobTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
    @subscription = create(:azure_devops_subscription, integration: @integration)
    stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
  end

  def perform(event_type:, resource:, occurred_at: nil)
    ResolveAzureDevopsEventJob.new.perform(
      subscription_id: @subscription.id, event_type: event_type, resource: resource, occurred_at: occurred_at
    )
  end

  # `repository` is included deliberately: gate routing follows AZURE's answer
  # about which repository the build ran against, not the id in the payload.
  def stub_build(id:, status: "completed", result: "succeeded", commit: "abc123", repository_id: nil)
    stub_request(:get, %r{/_apis/build/builds/#{id}}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: id, status: status, result: result, sourceVersion: commit,
              buildNumber: "20260912.1",
              repository: { id: repository_id || @repository.external_id } }.to_json
    )
  end

  test "re-reads the build rather than trusting the delivered result" do
    # The payload claims success; Azure says it failed. Azure wins.
    stub_build(id: 55, result: "failed")
    GateService.expects(:resolve_azure_devops_build).with(
      has_entries(build_id: 55, result: "failed")
    ).once

    perform(event_type: "build.complete",
            resource: { "id" => 55, "result" => "succeeded",
                        "repository" => { "id" => @repository.external_id } })
  end

  test "a build that is not finished resolves nothing" do
    stub_build(id: 55, status: "inProgress", result: nil)
    GateService.expects(:resolve_azure_devops_build).never

    perform(event_type: "build.complete",
            resource: { "id" => 55, "repository" => { "id" => @repository.external_id } })
  end

  # The merged event reports a merge ATTEMPT. What decides the gate is the
  # branch-policy evaluation, read back from Azure.
  test "a merged event resolves from branch policies, not from the event" do
    stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [ { evaluationId: "e1", status: "approved",
                         configuration: { isBlocking: true, isEnabled: true,
                                          type: { displayName: "Build" } } } ] }.to_json
    )
    stub_request(:get, %r{/pullrequests/9}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { pullRequestId: 9, status: "active", lastMergeSourceCommit: { commitId: "abc123" },
              repository: { id: @repository.external_id,
                            project: { id: @integration.azure_project_id } } }.to_json
    )

    GateService.expects(:resolve_azure_devops_pr_policies).with(
      has_entries(pull_request_id: 9, satisfied: true, commit: "abc123")
    ).once

    perform(event_type: "git.pullrequest.merged",
            resource: { "pullRequestId" => 9, "repository" => { "id" => @repository.external_id } })
  end

  test "a pull request with no blocking policies resolves nothing" do
    stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json
    )
    GateService.expects(:resolve_azure_devops_pr_policies).never

    perform(event_type: "git.pullrequest.merged",
            resource: { "pullRequestId" => 9, "repository" => { "id" => @repository.external_id } })
  end

  test "an event naming a repository this connection does not own is ignored" do
    GateService.expects(:resolve_azure_devops_pr_policies).never

    perform(event_type: "git.pullrequest.merged",
            resource: { "pullRequestId" => 9, "repository" => { "id" => SecureRandom.uuid } })
  end

  # A transient Azure failure must leave the gate pending for the reconciliation
  # sweep rather than retrying the job against a provider that is already unhappy.
  # The payload names a repository too, and it is NOT what routing follows: a
  # delivery on one project's subscription must not resolve gates in another
  # project that happens to hold that repository.
  test "a build whose repository this connection does not own resolves nothing" do
    stub_build(id: 55, repository_id: SecureRandom.uuid)
    GateService.expects(:resolve_azure_devops_build).never

    perform(event_type: "build.complete",
            resource: { "id" => 55, "repository" => { "id" => @repository.external_id } })
  end

  test "an Azure failure is swallowed so the reconciliation sweep can take over" do
    stub_request(:get, %r{/_apis/build/builds/55}).to_return(status: 503, body: "")

    assert_nothing_raised do
      perform(event_type: "build.complete",
              resource: { "id" => 55, "repository" => { "id" => @repository.external_id } })
    end
  end

  test "a disconnected integration does nothing" do
    @integration.update!(status: :inactive)
    GateService.expects(:resolve_azure_devops_build).never

    perform(event_type: "build.complete",
            resource: { "id" => 55, "repository" => { "id" => @repository.external_id } })
  end

  test "a work item event goes to the tracker pipeline, which re-reads the work item" do
    tracker = create(:project_tracker, integration: @integration)
    workflow = create(:workflow, scope: @integration.project)
    create(:trigger_binding, project: @integration.project, workflow: workflow, event_type: "tracker.issue.status_changed")
    subscription = create(:azure_devops_subscription, integration: @integration, event_type: "workitem.updated",
                                                      azure_project_id: tracker.external_scope_id)
    read = stub_request(:get, %r{/_apis/wit/workitems/308}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: 308, rev: 2, fields: { "System.TeamProject" => "Customer Platform", "System.Title" => "Sample task",
                                          "System.State" => "Approved", "System.WorkItemType" => "Task" } }.to_json
    )
    stub_request(:get, %r{/_apis/wit/workitemtypes}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [ { name: "Task", states: [ { name: "New", category: "Proposed" },
                                                  { name: "Approved", category: "InProgress" } ] } ] }.to_json
    )
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))

    ResolveAzureDevopsEventJob.new.perform(
      subscription_id: subscription.id, event_type: "workitem.updated",
      resource: { "id" => 5, "workItemId" => 308, "rev" => 2,
                  "fields" => { "System.State" => { "oldValue" => "New", "newValue" => "Approved" } } }
    )

    assert_requested read
    event = TriggerEvent.sole
    assert_equal [ "tracker.issue.status_changed", "Approved", "in_progress", "Sample task" ],
                 [ event.event_type, event.data.dig("change", "to", "name"), event.data.dig("change", "to", "category"),
                   event.data.dig("issue", "title") ]
  end

  test "a comment on a pull request of a repository this connection owns reaches pull-request triggers" do
    project = @integration.project
    create(:trigger_binding, project: project, workflow: create(:workflow, scope: project), created_by: project.owner,
                             event_type: "pull_request.comment.created")
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))
    resource = {
      "comment" => { "id" => 1, "content" => "Rename this", "commentType" => "text",
                     "author" => { "id" => "a1b2", "displayName" => "Ada" },
                     "_links" => { "threads" => { "href" => "https://dev.azure.com/o/_apis/git/repositories/r/pullRequests/5/threads/9" } } },
      "pullRequest" => { "pullRequestId" => 5, "title" => "Add retries", "repository" => { "id" => @repository.external_id } }
    }

    perform(event_type: "ms.vss-code.git-pullrequest-comment-event", resource: resource)
    perform(event_type: "ms.vss-code.git-pullrequest-comment-event",
            resource: resource.deep_merge("pullRequest" => { "repository" => { "id" => SecureRandom.uuid } }))

    event = TriggerEvent.sole
    assert_equal [ "pull_request.comment.created", "9/1", @repository.id ],
                 [ event.event_type, event.data.dig("comment", "id"), event.data.dig("repository", "id") ]
  end

  test "an update while a review trigger waits publishes the votes its pull request's threads record" do
    project = @integration.project
    create(:trigger_binding, project: project, workflow: create(:workflow, scope: project), created_by: project.owner,
                             event_type: "pull_request.review.submitted")
    WorkflowService.stubs(:enqueue).returns(build(:workflow_run))
    stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json
    )
    stub_request(:get, %r{/pullrequests/5/threads}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [ { id: 31, publishedDate: "2026-11-18T10:00:00Z",
                         identities: { "1" => { id: "a1b2", displayName: "Ada" } },
                         properties: { CodeReviewThreadType: { "$value": "VoteUpdate" },
                                       CodeReviewVoteResult: { "$value": "-10" },
                                       CodeReviewVotedByIdentity: { "$value": "1" } } } ] }.to_json
    )
    resource = { "pullRequestId" => 5, "title" => "Add retries", "repository" => { "id" => @repository.external_id } }

    # The vote's own update, then a push a minute later that finds it again.
    perform(event_type: "git.pullrequest.updated", resource: resource, occurred_at: "2026-11-18T10:00:01Z")
    perform(event_type: "git.pullrequest.updated", resource: resource, occurred_at: "2026-11-18T10:01:00Z")

    event = TriggerEvent.sole
    assert_equal [ "pull_request.review.submitted", "changes_requested", "Ada" ],
                 [ event.event_type, event.data.dig("review", "verdict"), event.data.dig("actor", "name") ]
  end

  test "an update reads no threads while no review trigger waits" do
    stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json
    )

    perform(event_type: "git.pullrequest.updated",
            resource: { "pullRequestId" => 5, "repository" => { "id" => @repository.external_id } })

    assert_not_requested(:get, %r{/threads})
  end
end
