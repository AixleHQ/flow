# frozen_string_literal: true

require "test_helper"

# The job's whole reason for existing: a Service Hook payload is a notification,
# not state. `git.pullrequest.merged` fires for a merge that FAILED on a conflict
# exactly as it does for one that landed, so believing the payload would mark CI
# green for a merge that never happened.
class ResolveAzureDevopsEventJobTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
    @subscription = create(:azure_devops_subscription, integration: @integration)
    stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
  end

  def perform(event_type:, resource:)
    ResolveAzureDevopsEventJob.new.perform(
      subscription_id: @subscription.id, event_type: event_type, resource: resource
    )
  end

  def stub_build(id:, status: "completed", result: "succeeded", commit: "abc123")
    stub_request(:get, %r{/_apis/build/builds/#{id}}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: id, status: status, result: result, sourceVersion: commit,
              buildNumber: "20260912.1" }.to_json
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
end
