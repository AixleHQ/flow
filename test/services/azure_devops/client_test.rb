# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract test for the request construction and error mapping every service
  # inherits: fixed host, per-segment encoding, per-family api-version, and the
  # status translation that decides whether a failed write is "failed" or
  # "unknown".
  class ClientTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @integration = create(:integration, :azure_devops, :active)
      stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      @client, @resolved = CredentialProvider.client_for(@integration)
    end

    test "encodes every path segment separately and picks the family's api-version" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/Customer%20Platform/_apis/git/repositories")
             .with(query: { "api-version" => "7.1" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json)

      @client.get("_apis", "git", "repositories", family: :git, project: "Customer Platform")

      assert_requested stub
    end

    test "work item comments use their own preview version, not the GA one" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/proj/_apis/wit/workItems/7/comments")
             .with(query: { "api-version" => "7.1-preview.4" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { comments: [] }.to_json)

      @client.get("_apis", "wit", "workItems", 7, "comments", family: :wit_comments, project: "proj")

      assert_requested stub
    end

    # Found against a live tenant: policy evaluations answers plain 7.1 with a
    # 400 VssInvalidPreviewVersionException. Every PR-policy gate probe was
    # coming back `validation_failed` instead of a verdict, so the gate went
    # stale on a pull request whose policies were perfectly readable.
    test "policy evaluations use their own preview version, not the GA one" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/proj/_apis/policy/evaluations")
             .with(query: hash_including({ "api-version" => "7.1-preview.1" }))
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json)

      @client.get("_apis", "policy", "evaluations", family: :policy, project: "proj",
                  params: { artifactId: "vstfs:///CodeReview/CodeReviewId/proj%2F7" })

      assert_requested stub
    end

    test "a path segment cannot smuggle a separator or a traversal" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/_apis/git/repositories/..%2F..%2Fadmin")
             .with(query: { "api-version" => "7.1" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")

      @client.get("_apis", "git", "repositories", "../../admin", family: :git)

      assert_requested stub
    end

    test "a 401 reacquires the token once and retries once" do
      token_stub = stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      call_count = 0
      stub_request(:get, %r{/_apis/test}).to_return do
        call_count += 1
        call_count == 1 ? { status: 401, body: "" } : { status: 200, headers: { "Content-Type" => "application/json" }, body: "{}" }
      end

      @client.get("_apis", "test")

      assert_equal 2, call_count
      assert_requested token_stub, at_least_times: 1
    end

    test "a second 401 is an authorization failure, not another retry" do
      stub_request(:get, %r{/_apis/test}).to_return(status: 401, body: "")

      assert_raises(NotAuthorized) { @client.get("_apis", "test") }
    end

    # 412 is in here because a failed JSON Patch `test` on /rev — the optimistic
    # lock the work item guard is built on — returns Precondition Failed, not
    # 409. It was missing, so every revision conflict reached the agent as a
    # generic provider error with no current revision to re-read.
    test "maps Azure statuses onto the adapter's stable codes" do
      {
        403 => PermissionDenied,
        404 => NotFound,
        409 => Conflict,
        412 => Conflict,
        400 => ValidationFailed
      }.each do |status, klass|
        stub_request(:get, %r{/_apis/case-#{status}}).to_return(
          status: status, headers: { "Content-Type" => "application/json" },
          body: { message: "Azure says no" }.to_json
        )

        assert_raises(klass) { @client.get("_apis", "case-#{status}") }
      end
    end

    test "a 429 carries Azure's own delay rather than a guessed quota" do
      stub_request(:post, %r{/_apis/throttled}).to_return(status: 429, headers: { "Retry-After" => "7" }, body: "")

      error = assert_raises(RateLimited) { @client.post("_apis", "throttled", body: {}) }
      assert_in_delta 7.0, error.retry_after, 0.01
    end

    test "a timed-out write is unknown, and a timed-out read is merely a timeout" do
      stub_request(:post, %r{/_apis/slow}).to_timeout
      stub_request(:get, %r{/_apis/slow}).to_timeout

      assert_raises(OutcomeUnknown) { @client.post("_apis", "slow", body: {}) }
      read_error = assert_raises(Error) { @client.get("_apis", "slow") }
      assert_equal "timeout", read_error.code
    end

    test "a 500 on a write is unknown rather than retried" do
      stub = stub_request(:post, %r{/_apis/boom}).to_return(status: 500, body: "")

      assert_raises(OutcomeUnknown) { @client.post("_apis", "boom", body: {}) }
      # Exactly once: a POST that got a 500 may already have been applied.
      assert_requested stub, times: 1
    end

    # Regression: System.TeamProject is the project NAME, so the old check
    # compared it to a GUID and could only ever fall through to a cached display
    # name — absent or stale, every work-item read failed permanently.
    test "a work item is scoped by project NAME, resolved from Azure when it is not cached" do
      @integration.settings = @integration.settings.except("azure_project_name")
      @integration.save!
      stub_request(:get, %r{/_apis/projects/#{@integration.azure_project_id}}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: @integration.azure_project_id, name: "Customer Platform" }.to_json
      )
      stub_request(:get, %r{/_apis/wit/workitems/11}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: 11, rev: 2, fields: { "System.TeamProject" => "Customer Platform",
                                          "System.Title" => "t" } }.to_json
      )

      item = WorkItemService.new(@integration).get(11)

      assert_equal 11, item[:id]
      # Resolved once and cached, so the next read does not pay for the lookup.
      assert_equal "Customer Platform", @integration.reload.azure_project_name
    end

    test "a work item from a neighbouring Azure project is refused" do
      stub_request(:get, %r{/_apis/wit/workitems/11}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: 11, rev: 2, fields: { "System.TeamProject" => "Someone Else" } }.to_json
      )

      error = assert_raises(NotAuthorized) { WorkItemService.new(@integration).get(11) }
      assert_match(/Someone Else/, error.message)
    end

    # Regression: update rescued ValidationFailed too and always re-raised it as a
    # revision conflict, so an agent told "changed since revision 7" re-read, saw
    # revision 7, and retried the same invalid request forever.
    test "a process-rule rejection is reported as a validation failure, not a conflict" do
      stub_request(:patch, %r{/_apis/wit/workitems/11}).to_return(
        status: 400, headers: { "Content-Type" => "application/json" },
        body: { message: "The field 'State' contains an invalid value" }.to_json
      )

      error = assert_raises(ValidationFailed) do
        WorkItemService.new(@integration).update(11, fields: { state: "Nope" }, expected_revision: 7)
      end
      assert_match(/invalid value/, error.message)
    end

    # Regression: escaping before truncating could cut an escaped '' pair in half
    # and ship an unterminated WIQL string literal.
    test "a long filter value ending in a quote stays balanced" do
      wiql = nil
      stub_request(:post, %r{/_apis/wit/wiql}).to_return do |req|
        wiql = JSON.parse(req.body)["query"]
        { status: 200, headers: { "Content-Type" => "application/json" }, body: { workItems: [] }.to_json }
      end

      WorkItemService.new(@integration).query(filters: { title_contains: "#{'a' * 199}'" })

      assert_equal 0, wiql.count("'") % 2, "WIQL has an unbalanced quote: #{wiql}"
    end

    # Regression, found only by talking to Azure: a stale revision comes back as
    # 412 with a TestPatchOperationFailedException, and the caller needs the
    # CURRENT revision to re-read — not a bare provider message.
    test "a stale work item revision is a conflict carrying the current revision" do
      stub_request(:patch, %r{/_apis/wit/workitems/11}).to_return(
        status: 412, headers: { "Content-Type" => "application/json" },
        body: { typeKey: "TestPatchOperationFailedException",
                message: "VS403351: Test Operation for path /rev failed" }.to_json
      )
      stub_request(:get, %r{/_apis/wit/workitems/11}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: 11, rev: 3, fields: { "System.TeamProject" => @integration.azure_project_name } }.to_json
      )

      error = assert_raises(Conflict) do
        WorkItemService.new(@integration).update(11, fields: { state: "Active" }, expected_revision: 1)
      end
      assert_equal({ current_revision: 3 }, error.details)
    end

    # Regression: Azure returns no `_links.web` for a pull request at all, so
    # reading one meant every result promised a url and shipped nothing.
    test "a pull request carries a browser url built from the repository's own" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:get, %r{/pullrequests/7}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { pullRequestId: 7, status: "active",
                repository: { id: repository.external_id,
                              project: { id: @integration.azure_project_id },
                              webUrl: "#{AZURE_API_HOST}/contoso/Proj/_git/api" } }.to_json
      )

      pr = PullRequestService.new(@integration).get(repository, 7)

      assert_equal "#{AZURE_API_HOST}/contoso/Proj/_git/api/pullrequest/7", pr[:url]
    end

    # A pull request with no branch policies is not blocked by anything, and
    # saying otherwise told a documentation-following agent not to merge it.
    # The two internal consumers branch on blocking_count first, so only the
    # tool ever saw the contradiction: count 0, unsatisfied [], verdict false.
    test "a pull request with no policies is reported as unblocked" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json
      )

      result = BuildService.new(@integration).policy_evaluations(repository, 7)

      assert_equal 0, result[:blocking_count]
      assert_empty result[:unsatisfied]
      assert result[:all_blocking_satisfied], "nothing blocking means nothing to satisfy"
    end

    test "an unapproved blocking policy is still reported as blocking" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:get, %r{/_apis/policy/evaluations}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { value: [ { evaluationId: "e1", status: "rejected",
                           configuration: { isBlocking: true, isEnabled: true,
                                            type: { displayName: "Minimum number of reviewers" } } } ] }.to_json
      )

      result = BuildService.new(@integration).policy_evaluations(repository, 7)

      assert_equal 1, result[:blocking_count]
      assert_not result[:all_blocking_satisfied]
      assert_equal [ "Minimum number of reviewers" ], result[:unsatisfied]
    end

    # Azure's reviewer endpoints are PUT on the reviewer itself. PATCH does not
    # 404 — it reaches a different handler and complains about `isFlagged` and
    # `hasDeclined`, which reads like a payload problem and is not one. Both
    # adding a reviewer and voting were sending PATCH, so neither worked at all,
    # and the complaint was mapped to "Azure does not recognize reviewer X" —
    # confidently wrong about a reviewer that existed.
    test "a reviewer is added with PUT on the reviewer itself" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      # Adding reads the current reviewers first, so an existing vote survives.
      stub_request(:get, %r{/pullrequests/7/reviewers}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json
      )
      stub_request(:put, %r{/pullrequests/7/reviewers/identity-1}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "identity-1", displayName: "Aixle Flow", vote: 0, isRequired: true }.to_json
      )

      PullRequestService.new(@integration).add_reviewer(repository, 7, reviewer_id: "identity-1", required: true)

      assert_requested(:put, %r{/pullrequests/7/reviewers/identity-1}) do |req|
        JSON.parse(req.body)["isRequired"] == true
      end
    end

    test "a vote is cast with PUT on the reviewer itself" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:put, %r{/pullrequests/7/reviewers/identity-1}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "identity-1", displayName: "Aixle Flow", vote: 10 }.to_json
      )

      PullRequestService.new(@integration).vote(repository, 7, reviewer_id: "identity-1", vote: "approve")

      assert_requested(:put, %r{/pullrequests/7/reviewers/identity-1}) do |req|
        JSON.parse(req.body)["vote"] == 10
      end
    end

    # The guard the description promised and did not have. Azure does NOT refuse
    # a completion whose `lastMergeSourceCommit` no longer matches — a
    # completion carrying an all-zeros commit id merged the branch anyway. So it
    # is compared here, against the same state the caller was told to read
    # `expected_commit` from.
    test "a pull request that moved since it was read is not completed" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:get, %r{/pullrequests/7}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { pullRequestId: 7, status: "active",
                lastMergeSourceCommit: { commitId: "b" * 40 },
                repository: { id: repository.external_id, project: { id: @integration.azure_project_id },
                              webUrl: "#{AZURE_API_HOST}/contoso/Proj/_git/api" } }.to_json
      )
      completion = stub_request(:patch, %r{/pullrequests/7})

      error = assert_raises(Conflict) do
        PullRequestService.new(@integration).complete(repository, 7, expected_commit: "a" * 40)
      end

      assert_equal({ current_commit: "b" * 40, expected_commit: "a" * 40 }, error.details)
      assert_not_requested completion
    end

    # Adding a reviewer is about membership. Sending a flat `vote: 0` reset an
    # existing approval — silently, and on a policy-protected branch that
    # un-blocks and re-blocks the merge.
    test "adding an existing reviewer keeps the vote they already cast" do
      repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)
      stub_request(:get, %r{/pullrequests/7/reviewers}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { value: [ { id: "identity-1", displayName: "Ada", vote: 10, isRequired: false } ] }.to_json
      )
      stub_request(:put, %r{/pullrequests/7/reviewers/identity-1}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "identity-1", displayName: "Ada", vote: 10, isRequired: true }.to_json
      )

      PullRequestService.new(@integration).add_reviewer(repository, 7, reviewer_id: "identity-1", required: true)

      assert_requested(:put, %r{/pullrequests/7/reviewers/identity-1}) do |req|
        body = JSON.parse(req.body)
        body["vote"] == 10 && body["isRequired"] == true
      end
    end

    test "paginate follows Azure's continuation header and stops at the limit" do
      base = "#{AZURE_API_HOST}/#{@resolved.organization}/_apis/paged"
      stub_request(:get, base).with(query: { "api-version" => "7.1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json", "x-ms-continuationtoken" => "page2" },
                   body: { value: [ { id: 1 } ] }.to_json)
      stub_request(:get, base).with(query: { "api-version" => "7.1", "continuationToken" => "page2" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ { id: 2 } ] }.to_json)

      items, more = @client.paginate("_apis", "paged", limit: 10)

      assert_equal [ 1, 2 ], items.map { |i| i["id"] }
      refute more
    end
  end
end
