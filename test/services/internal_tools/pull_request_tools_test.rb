# frozen_string_literal: true

require "test_helper"

# The pull_request_* tools over the canonical fake provider (R3); the adapters'
# own HTTP translation is pinned in test/services/pull_requests/, which is also
# where the fake is held to the adapters' contract (R4).
class InternalTools::PullRequestToolsTest < ActiveSupport::TestCase
  include PullRequestsTestHelper

  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :gitlab, :active, company: @company, project: @project, connected_by: @user)
    @repository = create(:repository, integration: @integration, scope: @project, full_name: "group/app",
                                      clone_url: "https://gitlab.com/group/app.git", source_branch: "develop")
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @session.repositories << @repository
    @fake = stub_pull_requests!
  end

  def run_tool(klass, params, session: @session)
    klass.new(params: params, session: session).execute
  end

  def json(result) = JSON.parse(result[:stdout].presence || result[:stderr])

  # == target resolution ==

  test "a repository not attached to this session is refused" do
    other = create(:repository, integration: @integration, scope: @project, full_name: "group/other",
                                clone_url: "https://gitlab.com/group/other.git")

    result = run_tool(InternalTools::PullRequestList, { repository_id: other.id })

    assert_equal 1, result[:exit_code]
    assert_equal "not_authorized", json(result)["error"]
  end

  test "a repository whose connection belongs to another company is refused even when attached" do
    foreign = create(:integration, :gitlab, :active)
    foreign_project = create(:project, company: foreign.company, owner: create(:user, company: foreign.company))
    foreign_repository = create(:repository, integration: foreign, scope: foreign_project,
                                             full_name: "evil/app", clone_url: "https://gitlab.com/evil/app.git")
    @session.repositories << foreign_repository

    result = run_tool(InternalTools::PullRequestList, { repository_id: foreign_repository.id })

    assert_equal "not_authorized", json(result)["error"]
    assert_match "another project", json(result)["message"]
  end

  test "a public repository, which has no connection to act as, is refused" do
    public_repo = create(:repository, :public_source, scope: @project, full_name: "torvalds/linux",
                                                      clone_url: "https://github.com/torvalds/linux.git")
    @session.repositories << public_repo

    result = run_tool(InternalTools::PullRequestList, { repository_id: public_repo.id })

    assert_equal "validation_failed", json(result)["error"]
  end

  test "the session's only pull-request repository is the default target" do
    @fake.add_pull_request(@repository, number: 3)

    result = run_tool(InternalTools::PullRequestList, {})

    assert_equal 0, result[:exit_code]
    assert_equal @repository.id, json(result)["repository_id"]
    assert_equal [ 3 ], json(result)["pull_requests"].map { |pr| pr["number"] }
  end

  test "with several candidates, a URL picks its owner and nothing else guesses" do
    second = create(:repository, integration: @integration, scope: @project, full_name: "group/web",
                                 clone_url: "https://gitlab.com/group/web.git")
    @session.repositories << second
    @fake.add_pull_request(second, number: 4)

    ambiguous = run_tool(InternalTools::PullRequestGet, { pull_request: "4" })
    by_url = run_tool(InternalTools::PullRequestGet, { pull_request: "#{@fake.url_base(second)}/4" })

    assert_equal "repository_required", json(ambiguous)["error"]
    assert_equal [ @repository.id, second.id ], json(ambiguous).dig("details", "candidates").map { |c| c["repository_id"] }
    assert_equal second.id, json(by_url)["repository_id"]
  end

  test "a connection that needs attention says so before any provider call" do
    @integration.update!(status: :error)

    result = run_tool(InternalTools::PullRequestList, {})

    assert_equal "integration_unavailable", json(result)["error"]
    assert_empty @fake.calls
  end

  test "a provider error reaches the agent as its stable code" do
    @fake.fail_next(:get, PullRequests::Error.new("gone", code: "not_found_or_inaccessible"))

    result = run_tool(InternalTools::PullRequestGet, { pull_request: "9" })

    assert_equal({ "error" => "not_found_or_inaccessible", "message" => "gone" }, json(result))
  end

  # == create ==

  test "create opens a draft into the repository's session branch and records it" do
    result = run_tool(InternalTools::PullRequestCreate, { source_branch: "feature/login", title: "Add login" })

    body = json(result)
    assert_equal 0, result[:exit_code]
    assert_equal false, body["existing"] # rubocop:disable Minitest/RefuteFalse
    assert_equal "develop", body.dig("pull_request", "target_branch")
    assert body.dig("pull_request", "draft")
    operation = PullRequestOperation.sole
    assert_equal [ "create", "succeeded", body.dig("pull_request", "number").to_s, @session.id ],
                 [ operation.operation, operation.state, operation.pull_request_number, operation.terminal_session_id ]
  end

  test "an identical retry replays the first result instead of opening a second" do
    params = { source_branch: "feature/login", target_branch: "main", title: "Add login" }

    first = json(run_tool(InternalTools::PullRequestCreate, params))
    second = json(run_tool(InternalTools::PullRequestCreate, params))

    assert second["replayed"]
    assert_equal first.dig("pull_request", "number"), second.dig("pull_request", "number")
    assert_equal 1, @fake.calls.count { |call| call.name == :create }
  end

  test "a pull request already open from the same branch is returned, not duplicated" do
    @fake.add_pull_request(@repository, number: 11, source_branch: "feature/login", target_branch: "develop")

    body = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "feature/login", title: "Again" }))

    assert body["existing"]
    assert_equal 11, body.dig("pull_request", "number")
    assert_not @fake.called?(:create)
  end

  test "a key reused for a different request is a conflict" do
    run_tool(InternalTools::PullRequestCreate, { source_branch: "a", title: "One", operation_key: "k1" })

    result = run_tool(InternalTools::PullRequestCreate, { source_branch: "b", title: "Two", operation_key: "k1" })

    assert_equal "conflict", json(result)["error"]
  end

  test "an unanswered write is unknown, and its retry says so rather than writing again" do
    @fake.fail_next(:create, PullRequests::Error::OutcomeUnknown.new("GitLab did not confirm the request"))
    params = { source_branch: "feature/login", title: "Add login", operation_key: "k2" }

    first = json(run_tool(InternalTools::PullRequestCreate, params))
    second = json(run_tool(InternalTools::PullRequestCreate, params))

    assert_equal [ "outcome_unknown", "outcome_unknown" ], [ first["error"], second["error"] ]
    assert_equal "unknown", PullRequestOperation.sole.state
    assert_equal 1, @fake.calls.count { |call| call.name == :create }
  end

  test "a refused write may be sent again" do
    @fake.add_pull_request(@repository, number: 5)
    @fake.fail_next(:add_comment, PullRequests::Error.new("nope", code: "validation_failed"))
    params = { pull_request: "5", body: "LGTM" }

    refused = run_tool(InternalTools::PullRequestAddComment, params)
    retried = run_tool(InternalTools::PullRequestAddComment, params)

    assert_equal "validation_failed", json(refused)["error"]
    assert_equal 0, retried[:exit_code]
    assert_equal [ "LGTM" ], @fake.comments_on(@repository, 5).map(&:body)
  end

  test "in a run started from a tracker issue the title carries the issue key, once" do
    session = tracker_session("ENG-123")

    keyed = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "eng-1", title: "Fix login" }, session: session))
    already = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "eng-2", title: "eng-123 fix logout" },
                            session: session))

    assert_equal "ENG-123: Fix login", keyed.dig("pull_request", "title")
    assert_equal "eng-123 fix logout", already.dig("pull_request", "title")
  end

  test "outside a tracker run the title is left alone" do
    body = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "feature/x", title: "Plain" }))

    assert_equal "Plain", body.dig("pull_request", "title")
  end

  # == update, comments, review ==

  test "update changes only what was passed and refuses an empty change" do
    @fake.add_pull_request(@repository, number: 6, title: "Old")

    empty = run_tool(InternalTools::PullRequestUpdate, { pull_request: "6" })
    changed = json(run_tool(InternalTools::PullRequestUpdate, { pull_request: "6", title: "New", draft: true }))

    assert_equal "validation_failed", json(empty)["error"]
    assert_equal [ "New", true ], [ changed.dig("pull_request", "title"), changed.dig("pull_request", "draft") ]
  end

  test "an inline comment and a review go through the ledger" do
    @fake.add_pull_request(@repository, number: 6)

    comment = json(run_tool(InternalTools::PullRequestAddComment, { pull_request: "6", body: "Nit", file_path: "a.rb", line: 3 }))
    review = json(run_tool(InternalTools::PullRequestReview, { pull_request: "6", verdict: "approve" }))

    assert_equal [ "a.rb", 3 ], [ comment["file_path"], comment["line"] ]
    assert_equal "approve", review["verdict"]
    assert_equal %w[add_comment review], PullRequestOperation.order(:id).pluck(:operation)
    assert_equal %w[6 6], PullRequestOperation.order(:id).pluck(:pull_request_number)
  end

  test "a pull request this connection opened cannot be approved by it" do
    created = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "feature/x", title: "Change" }))

    refused = json(run_tool(InternalTools::PullRequestReview, { pull_request: created.dig("pull_request", "number").to_s, verdict: "approve" }))
    changes = json(run_tool(InternalTools::PullRequestReview, { pull_request: created.dig("pull_request", "number").to_s,
                                                                verdict: "request_changes", body: "Not yet" }))

    assert_equal "permission_denied", refused["error"]
    assert_equal "request_changes", changes["verdict"]
  end

  test "a pull request found already open was not opened here, and may be approved" do
    @fake.add_pull_request(@repository, number: 9, source_branch: "feature/y", target_branch: @repository.source_branch)

    found = json(run_tool(InternalTools::PullRequestCreate, { source_branch: "feature/y", title: "Change" }))
    review = json(run_tool(InternalTools::PullRequestReview, { pull_request: "9", verdict: "approve" }))

    assert found["existing"]
    assert_equal "approve", review["verdict"]
  end

  test "read tools answer the provider's values" do
    @fake.add_pull_request(@repository, number: 6)
    @fake.set_checks(@repository, 6, state: "passed", items: [ { name: "rspec", status: "passed", url: nil } ])

    checks = json(run_tool(InternalTools::PullRequestChecks, { pull_request: "6" }))
    files = json(run_tool(InternalTools::PullRequestChanges, { pull_request: "6" }))
    comments = json(run_tool(InternalTools::PullRequestListComments, { pull_request: "6" }))

    assert_equal "passed", checks.dig("checks", "state")
    assert_equal [ "app/models/user.rb" ], files["files"].map { |f| f["path"] }
    assert_equal [], comments["comments"]
  end

  # == merge ==

  test "merge refuses a head that moved since review, and merges nothing" do
    @fake.add_pull_request(@repository, number: 8, head_sha: "b" * 40)

    result = run_tool(InternalTools::PullRequestMerge, { pull_request: "8", expected_head_sha: "a" * 40 })

    assert_equal "conflict", json(result)["error"]
    assert_equal "b" * 40, json(result).dig("details", "current_head_sha")
    assert_not @fake.called?(:merge)
  end

  test "merge at the reviewed head merges" do
    @fake.add_pull_request(@repository, number: 8, head_sha: "b" * 40)

    body = json(run_tool(InternalTools::PullRequestMerge, { pull_request: "8", expected_head_sha: "b" * 40,
                                                            strategy: "squash" }))

    assert body["merged"]
    assert_equal "merged", body.dig("pull_request", "state")
    assert_equal "merge", PullRequestOperation.sole.operation
  end

  test "merge is refused when the connection turned merging off" do
    @integration.update!(settings: @integration.settings.to_h.merge("pull_request_merge" => false))
    @fake.add_pull_request(@repository, number: 8, head_sha: "b" * 40)

    result = run_tool(InternalTools::PullRequestMerge, { pull_request: "8", expected_head_sha: "b" * 40 })

    assert_equal "permission_denied", json(result)["error"]
    assert_empty @fake.calls
  end

  test "merge without the reviewed head is refused" do
    result = run_tool(InternalTools::PullRequestMerge, { pull_request: "8", expected_head_sha: " " })

    assert_equal "validation_failed", json(result)["error"]
  end

  # == injection ==

  test "the tools come with a GitHub, GitLab or Bitbucket repository, and not with an Azure or public one" do
    definition = Tools::Registry.fetch("pull_request_merge")
    bitbucket = create(:repository, :bitbucket)
    bitbucket_session = create(:terminal_session, :running, user: @user, project: bitbucket.scope)
    bitbucket_session.repositories << bitbucket
    github_session = create(:terminal_session, :running, user: @user, project: @project)
    github_session.repositories << create(:repository, scope: @project,
                                                       integration: create(:integration, :active, company: @company))

    public_session = create(:terminal_session, :running, user: @user, project: @project)
    public_session.repositories << create(:repository, :public_source, scope: @project, full_name: "torvalds/linux",
                                                                       clone_url: "https://github.com/torvalds/linux.git")
    azure = create(:repository, :azure_devops)
    azure_session = create(:terminal_session, :running, user: @user, project: azure.scope)
    azure_session.repositories << azure

    assert definition.inject?(Tools::Context.for_session(@session))
    assert definition.inject?(Tools::Context.for_session(bitbucket_session))
    assert definition.inject?(Tools::Context.for_session(github_session))
    assert_not definition.inject?(Tools::Context.for_session(public_session))
    assert_not definition.inject?(Tools::Context.for_session(azure_session))
    assert definition.available?(Tools::Context.for_session(@session))
    assert_not definition.user_attachable
    assert_includes @session.available_tools.map(&:name), "pull_request_create"
  end

  private

  def tracker_session(key)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user,
                                          shared_context: { "tracker" => { "handle" => "jira", "issue" => { "key" => key, "id" => "10001" } } })
    step_run = create(:step_run, :running, workflow_run: run, step: create(:step, workflow: workflow))
    session = create(:terminal_session, :running, user: @user, project: @project, step_run: step_run)
    session.repositories << @repository
    session
  end
end
