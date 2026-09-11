# frozen_string_literal: true

require "test_helper"

# The parity-extension tools: reviewers, votes, branch policies, builds and
# completion. Completion carries the guards the design insists on, and they are
# what most of this file is about.
class InternalTools::AzureDevopsParityToolsTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @integration = create(:integration, :azure_devops, :active, company: @company, connected_by: @user,
                                        enabled_capabilities: AzureDevops::IntegrationService::ALL_CAPABILITIES)
    @project = @integration.project
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @project)
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @session.repositories << @repository
    stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
  end

  def run_tool(klass, params)
    klass.new(params: params, session: @session).execute
  end

  def pr_body(status: "active", commit: "abc123")
    {
      pullRequestId: 9, title: "Fix", status: status, isDraft: false,
      sourceRefName: "refs/heads/feature/1", targetRefName: "refs/heads/main",
      lastMergeSourceCommit: { commitId: commit },
      repository: { id: @repository.external_id, project: { id: @integration.azure_project_id } }
    }
  end

  # == completion guards ==

  # Merging is not something to acquire by accepting a form's defaults, so a
  # connection created with the defaults cannot do it at all.
  test "completion is refused on a connection that did not enable it" do
    @integration.settings = @integration.settings.merge(
      "enabled_capabilities" => AzureDevops::IntegrationService::DEFAULT_CAPABILITIES
    )
    @integration.save!

    result = run_tool(InternalTools::AzureDevopsCompletePullRequest, {
      repository_id: @repository.id, pull_request_id: 9,
      expected_commit: "abc123", operation_key: "c1"
    })

    assert_equal 1, result[:exit_code]
    assert_match(/pull_requests.complete/, result[:stderr])
    assert_not_requested :patch, %r{/pullrequests/9}
  end

  test "completion sends the expected source commit and never bypasses policy" do
    stub_request(:patch, %r{/pullrequests/9})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_body.to_json)
    stub_request(:get, %r{/pullrequests/9})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: pr_body(status: "completed").to_json)

    result = run_tool(InternalTools::AzureDevopsCompletePullRequest, {
      repository_id: @repository.id, pull_request_id: 9,
      expected_commit: "abc123", merge_strategy: "squash", operation_key: "c2"
    })

    assert_equal 0, result[:exit_code]
    assert JSON.parse(result[:stdout])["completed"]
    assert_requested(:patch, %r{/pullrequests/9}) do |req|
      body = JSON.parse(req.body)
      body.dig("lastMergeSourceCommit", "commitId") == "abc123" &&
        body.dig("completionOptions", "bypassPolicy") == false &&
        body.dig("completionOptions", "mergeStrategy") == "squash"
    end
  end

  # Azure completes asynchronously, so a 200 means "accepted". Reporting that as
  # a merge is how an agent moves on from a pull request that is still blocked.
  test "a pull request still active after completion is reported as pending, not merged" do
    stub_request(:patch, %r{/pullrequests/9})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_body.to_json)
    stub_request(:get, %r{/pullrequests/9})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_body.to_json)

    result = run_tool(InternalTools::AzureDevopsCompletePullRequest, {
      repository_id: @repository.id, pull_request_id: 9,
      expected_commit: "abc123", operation_key: "c3"
    })

    body = JSON.parse(result[:stdout])
    assert_equal false, body["completed"] # rubocop:disable Minitest/RefuteFalse
    assert body["pending"]
    assert_match(/has not finished merging/, body["note"])
  end

  test "an unknown merge strategy is refused before anything is sent" do
    result = run_tool(InternalTools::AzureDevopsCompletePullRequest, {
      repository_id: @repository.id, pull_request_id: 9, expected_commit: "abc123",
      merge_strategy: "forcePush", operation_key: "c4"
    })

    assert_equal 1, result[:exit_code]
    assert_match(/merge_strategy/, result[:stderr])
    assert_not_requested :patch, %r{/pullrequests/9}
  end

  # == policies ==

  test "policy evaluations report what is still blocking rather than a build result" do
    stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [
        { evaluationId: "e1", status: "approved",
          configuration: { isBlocking: true, isEnabled: true, type: { displayName: "Build" } } },
        { evaluationId: "e2", status: "queued",
          configuration: { isBlocking: true, isEnabled: true,
                           type: { displayName: "Minimum number of reviewers" } } }
      ] }.to_json
    )

    result = run_tool(InternalTools::AzureDevopsGetPullRequestPolicies,
                      { repository_id: @repository.id, pull_request_id: 9 })

    body = JSON.parse(result[:stdout])
    assert_equal false, body["all_blocking_satisfied"] # rubocop:disable Minitest/RefuteFalse
    assert_equal [ "Minimum number of reviewers" ], body["unsatisfied"]
    assert_equal 2, body["blocking_count"]
  end

  # == reviewers and votes ==

  test "votes translate a named verdict into Azure's numeric vocabulary" do
    stub_request(:patch, %r{/pullrequests/9/reviewers/rev-1}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "rev-1", displayName: "Aixle", vote: 10, isRequired: false }.to_json
    )

    result = run_tool(InternalTools::AzureDevopsVotePullRequest, {
      repository_id: @repository.id, pull_request_id: 9, reviewer_id: "rev-1", vote: "approve"
    })

    assert_equal 0, result[:exit_code]
    assert_equal "approve", JSON.parse(result[:stdout])["vote_label"]
    assert_requested(:patch, %r{/pullrequests/9/reviewers/rev-1}) { |req| JSON.parse(req.body)["vote"] == 10 }
  end

  test "reviewers are listed with a readable label for Azure's numeric vote" do
    stub_request(:get, %r{/pullrequests/9/reviewers}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [ { id: "rev-1", displayName: "Ada", vote: -10, isRequired: true } ] }.to_json
    )

    result = run_tool(InternalTools::AzureDevopsListPullRequestReviewers,
                      { repository_id: @repository.id, pull_request_id: 9 })

    reviewer = JSON.parse(result[:stdout])["reviewers"].first
    assert_equal "reject", reviewer["vote_label"]
    assert reviewer["required"]
  end

  # == builds ==

  test "listing builds filters by repository with the type Azure requires" do
    stub_request(:get, %r{/_apis/build/builds}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { value: [ { id: 1, status: "completed", result: "succeeded",
                         sourceBranch: "refs/heads/main", sourceVersion: "abc" } ] }.to_json
    )

    result = run_tool(InternalTools::AzureDevopsListBuilds,
                      { integration_id: @integration.id, repository_id: @repository.id, branch: "main" })

    assert_equal 0, result[:exit_code]
    assert_equal "main", JSON.parse(result[:stdout])["builds"].first["branch"]
    assert_requested(:get, %r{/_apis/build/builds}) do |req|
      query = CGI.unescape(req.uri.query.to_s)
      query.include?("repositoryType=TfsGit") && query.include?("branchName=refs/heads/main")
    end
  end

  test "builds cannot be read without the builds.read capability" do
    @integration.settings = @integration.settings.merge("enabled_capabilities" => [ "repositories.read" ])
    @integration.save!

    result = run_tool(InternalTools::AzureDevopsListBuilds, { integration_id: @integration.id })

    assert_equal 1, result[:exit_code]
    assert_match(/builds.read/, result[:stderr])
  end
end
