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
    @fakes = stub_azure_devops!(integration: @integration)
  end

  def run_tool(klass, params)
    klass.new(params: params, session: @session).execute
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
    assert_empty @fakes.pull_requests.calls_to(:complete)
  end

  # That the request carries lastMergeSourceCommit and bypassPolicy: false is
  # pinned by the adapter's own contract test; here the tool's job is to forward
  # the commit the agent claims to have reviewed rather than dropping it.
  test "completion forwards the expected source commit and the chosen strategy" do
    result = run_tool(InternalTools::AzureDevopsCompletePullRequest, {
      repository_id: @repository.id, pull_request_id: 9,
      expected_commit: "abc123", merge_strategy: "squash", operation_key: "c2"
    })

    assert_equal 0, result[:exit_code]
    assert JSON.parse(result[:stdout])["completed"]
    call = @fakes.pull_requests.last_call
    assert_equal :complete, call[:method]
    assert_equal "abc123", call[:expected_commit]
    assert_equal "squash", call[:merge_strategy]
  end

  # Azure completes asynchronously, so a 200 means "accepted". Reporting that as
  # a merge is how an agent moves on from a pull request that is still blocked.
  test "a pull request still active after completion is reported as pending, not merged" do
    @fakes = stub_azure_devops!(integration: @integration, pull_requests: { completed: false })

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
    assert_empty @fakes.pull_requests.calls_to(:complete)
  end

  # == policies ==

  test "policy evaluations report what is still blocking rather than a build result" do
    @fakes = stub_azure_devops!(integration: @integration, builds: {
      policies: {
        pull_request_id: 9, blocking_count: 2, all_blocking_satisfied: false,
        unsatisfied: [ "Minimum number of reviewers" ],
        evaluations: [ { id: "e1", status: "approved", type: "Build", blocking: true },
                       { id: "e2", status: "queued", type: "Minimum number of reviewers", blocking: true } ]
      }
    })

    result = run_tool(InternalTools::AzureDevopsGetPullRequestPolicies,
                      { repository_id: @repository.id, pull_request_id: 9 })

    body = JSON.parse(result[:stdout])
    assert_equal false, body["all_blocking_satisfied"] # rubocop:disable Minitest/RefuteFalse
    assert_equal [ "Minimum number of reviewers" ], body["unsatisfied"]
    assert_equal 2, body["blocking_count"]
  end

  # == reviewers and votes ==

  test "votes translate a named verdict into Azure's numeric vocabulary" do
    result = run_tool(InternalTools::AzureDevopsVotePullRequest, {
      repository_id: @repository.id, pull_request_id: 9, reviewer_id: "rev-1", vote: "approve"
    })

    assert_equal 0, result[:exit_code]
    body = JSON.parse(result[:stdout])
    assert_equal "approve", body["vote_label"]
    assert_equal 10, body["vote"]
  end

  test "an unknown verdict is refused rather than posted as a bare integer" do
    result = run_tool(InternalTools::AzureDevopsVotePullRequest, {
      repository_id: @repository.id, pull_request_id: 9, reviewer_id: "rev-1", vote: "lgtm"
    })

    assert_equal 1, result[:exit_code]
    assert_empty @fakes.pull_requests.calls_to(:vote)
  end

  test "reviewers are listed with a readable label for Azure's numeric vote" do
    result = run_tool(InternalTools::AzureDevopsListPullRequestReviewers,
                      { repository_id: @repository.id, pull_request_id: 9 })

    reviewer = JSON.parse(result[:stdout])["reviewers"].first
    assert_equal "reset", reviewer["vote_label"]
    assert reviewer["required"]
  end

  # == builds ==

  # That the query carries repositoryType=TfsGit — without which Azure silently
  # ignores the repository filter — is pinned by the adapter's contract test.
  test "listing builds scopes to the repository and branch the caller named" do
    result = run_tool(InternalTools::AzureDevopsListBuilds,
                      { integration_id: @integration.id, repository_id: @repository.id, branch: "main" })

    assert_equal 0, result[:exit_code]
    assert_equal "main", JSON.parse(result[:stdout])["builds"].first["branch"]
    call = @fakes.builds.last_call
    assert_equal @repository.id, call[:repository].id
    assert_equal "main", call[:branch]
  end

  test "a repository belonging to another connection is refused" do
    other = create(:integration, :azure_devops, :active, company: @company, connected_by: @user)
    foreign = create(:repository, :azure_devops, integration: other, scope: other.project)
    @session.repositories << foreign

    result = run_tool(InternalTools::AzureDevopsListBuilds,
                      { integration_id: @integration.id, repository_id: foreign.id })

    assert_equal 1, result[:exit_code]
    assert_empty @fakes.builds.calls_to(:list)
  end

  test "builds cannot be read without the builds.read capability" do
    @integration.settings = @integration.settings.merge("enabled_capabilities" => [ "repositories.read" ])
    @integration.save!

    result = run_tool(InternalTools::AzureDevopsListBuilds, { integration_id: @integration.id })

    assert_equal 1, result[:exit_code]
    assert_match(/builds.read/, result[:stderr])
  end
end
