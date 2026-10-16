# frozen_string_literal: true

require "test_helper"

module Bitbucket
  # Contract test for the Bitbucket::Api adapter against Bitbucket Cloud's REST
  # 2.0 payloads (field names from the published OpenAPI spec), and the pin that
  # keeps FakeBitbucket::Api answering in the same shapes (docs/testing.md R4).
  class ApiTest < ActiveSupport::TestCase
    WS = "{8f1d6b2a-0000-4000-8000-00000000b17b}"
    REPO = "{5e4d3c2b-0000-4000-8000-0000000000a1}"
    WS_PATH = "%7B8f1d6b2a-0000-4000-8000-00000000b17b%7D"
    REPO_PATH = "%7B5e4d3c2b-0000-4000-8000-0000000000a1%7D"

    REPOSITORY = {
      "type" => "repository", "full_name" => "acme/api", "name" => "api", "uuid" => REPO.upcase,
      "is_private" => true, "description" => "Billing API", "mainbranch" => { "type" => "branch", "name" => "main" },
      "project" => { "type" => "project", "key" => "PRJ", "uuid" => "{3C2B1A00-0000-4000-8000-0000000000AA}" },
      "workspace" => { "type" => "workspace", "slug" => "acme", "uuid" => WS, "name" => "Acme" },
      "links" => { "clone" => [ { "name" => "https", "href" => "https://bitbucket.org/acme/api.git" } ] }
    }.freeze

    PULL_REQUEST = {
      "type" => "pullrequest", "id" => 7, "title" => "Add billing", "state" => "OPEN", "draft" => false,
      "summary" => { "raw" => "Adds the billing endpoint", "markup" => "markdown" },
      "author" => { "display_name" => "Aixle Flow", "uuid" => "{bot}" },
      "source" => { "branch" => { "name" => "feature" }, "commit" => { "hash" => "e3c6ad85c1b5" },
                    "repository" => { "uuid" => REPO } },
      "destination" => { "branch" => { "name" => "main" }, "commit" => { "hash" => "0a1b2c3d4e5f" },
                         "repository" => { "uuid" => REPO } },
      "reviewers" => [ { "display_name" => "Ada Lovelace" } ],
      "participants" => [ { "role" => "REVIEWER", "approved" => true, "state" => "approved",
                            "user" => { "display_name" => "Ada Lovelace" }, "participated_on" => "2026-10-16T09:10:00+00:00" } ],
      "merge_commit" => nil, "created_on" => "2026-10-16T09:00:00.000000+00:00",
      "updated_on" => "2026-10-16T09:30:00.000000+00:00"
    }.freeze

    COMMENT = {
      "type" => "pullrequest_comment", "id" => 501, "deleted" => false,
      "content" => { "raw" => "Please add a test", "markup" => "markdown" },
      "user" => { "display_name" => "Ada Lovelace" }, "inline" => { "path" => "app/billing.rb", "to" => 12, "from" => nil },
      "parent" => { "id" => 500 }, "resolution" => nil, "created_on" => "2026-10-16T09:12:00.000000+00:00"
    }.freeze

    setup do
      with_bitbucket_settings
      @api = Api.new(Credential.new(token: "tok", kind: :access_token))
    end

    def json(body, status: 200, headers: {})
      { status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: body.to_json }
    end

    def repo_url(*rest) = "#{BITBUCKET_API}/repositories/#{WS_PATH}/#{REPO_PATH}#{rest.map { |s| "/#{s}" }.join}"

    test "a repository comes back with braced, lowercase UUIDs and its workspace and project" do
      stub_request(:get, repo_url).to_return(json(REPOSITORY))

      repository = @api.repository(WS, REPO)

      assert_equal REPO, repository[:uuid]
      assert_equal WS, repository[:workspace_uuid]
      assert_equal "{3c2b1a00-0000-4000-8000-0000000000aa}", repository[:project_uuid]
      assert_equal "acme/api", repository[:full_name]
      assert_equal "api", repository[:slug]
      assert_equal "main", repository[:default_branch]
      assert repository[:is_private]
    end

    test "lists the workspace's repositories the credential is a member of" do
      stub = stub_request(:get, "#{BITBUCKET_API}/repositories/acme")
             .with(query: { "pagelen" => "100", "role" => "member" })
             .to_return(json({ "values" => [ REPOSITORY ] }))

      assert_equal [ "acme/api" ], @api.repositories("acme").map { |r| r[:full_name] }
      assert_requested stub
    end

    test "a repository sample asks for one small page" do
      stub = stub_request(:get, "#{BITBUCKET_API}/repositories/acme").with(query: { "pagelen" => "2" })
                                                                    .to_return(json({ "values" => [ REPOSITORY ] }))

      assert_equal [ "acme/api" ], @api.repository_sample("acme").map { |r| r[:full_name] }
      assert_requested stub
    end

    test "the current user, for a token that has one" do
      stub_request(:get, "#{BITBUCKET_API}/user")
        .to_return(json({ "uuid" => "{4A5B6C7D-0000-4000-8000-0000000000AA}", "account_id" => "557058:ada",
                          "display_name" => "Ada Lovelace", "nickname" => "ada" }))

      assert_equal({ uuid: "{4a5b6c7d-0000-4000-8000-0000000000aa}", account_id: "557058:ada",
                     display_name: "Ada Lovelace", nickname: "ada" }, @api.current_user)
    end

    # WebMock folds a repeated parameter into its last value unless told to keep
    # them, which would hide the very thing this test is about.
    test "lists pull requests with repeated state parameters and a BBQL branch filter" do
      notation = WebMock::Config.instance.query_values_notation
      WebMock::Config.instance.query_values_notation = :flat_array
      stub = stub_request(:get, /#{Regexp.escape(repo_url('pullrequests'))}\?/)
             .with do |request|
               pairs = request.uri.query_values(Array)
               pairs.select { |key, _| key == "state" }.map(&:last) == %w[DECLINED SUPERSEDED] &&
                 pairs.to_h.slice("pagelen", "q") == { "pagelen" => "50", "q" => 'source.branch.name="fe\"ature"' }
             end
             .to_return(json({ "values" => [ PULL_REQUEST ], "next" => "#{repo_url('pullrequests')}?page=2" }))

      items, cursor = @api.pull_requests(WS, REPO, state: "closed", source_branch: 'fe"ature', limit: 80)

      assert_requested stub
      assert_equal "2", cursor
      pr = items.first
      assert_equal 7, pr[:id]
      assert_equal "Adds the billing endpoint", pr[:description]
      assert_equal "e3c6ad85c1b5", pr[:source_commit]
      assert_equal "main", pr[:destination_branch]
      assert_equal REPO, pr[:destination_repository_uuid]
      assert_equal [ "Ada Lovelace" ], pr[:reviewers]
      assert pr[:participants].first[:approved]
    ensure
      WebMock::Config.instance.query_values_notation = notation
    end

    test "creates a pull request with source, destination and draft" do
      stub = stub_request(:post, repo_url("pullrequests"))
             .with(body: { title: "Add billing", source: { branch: { name: "feature" } }, draft: true,
                           description: "Why", close_source_branch: false, destination: { branch: { name: "main" } } })
             .to_return(json(PULL_REQUEST, status: 201))

      @api.create_pull_request(WS, REPO, title: "Add billing", source_branch: "feature", target_branch: "main",
                                         description: "Why", draft: true)

      assert_requested stub
    end

    test "a merge Bitbucket finishes at once answers the pull request" do
      stub_request(:post, repo_url("pullrequests", 7, "merge"))
        .with(body: { merge_strategy: "squash", close_source_branch: true })
        .to_return(json(PULL_REQUEST.merge("state" => "MERGED", "merge_commit" => { "hash" => "f00dfeed1234" })))

      result = @api.merge_pull_request(WS, REPO, 7, strategy: "squash", close_source_branch: true)

      assert_equal "MERGED", result[:pull_request][:state]
      assert_equal "f00dfeed1234", result[:pull_request][:merge_commit]
    end

    test "a merge Bitbucket queues answers the task id from the Location header" do
      stub_request(:post, repo_url("pullrequests", 7, "merge"))
        .to_return(status: 202, headers: { "Location" => "#{repo_url('pullrequests', 7, 'merge', 'task-status', 'abc-123')}" })
      stub_request(:get, repo_url("pullrequests", 7, "merge", "task-status", "abc-123"))
        .to_return(json({ "task_status" => "SUCCESS", "merge_result" => PULL_REQUEST.merge("state" => "MERGED") }))

      assert_equal({ task_id: "abc-123" }, @api.merge_pull_request(WS, REPO, 7))
      task = @api.merge_task(WS, REPO, 7, "abc-123")
      assert_equal "SUCCESS", task[:status]
      assert_equal "MERGED", task[:pull_request][:state]
    end

    test "comments come back with their thread and inline position, deleted ones dropped" do
      stub_request(:get, repo_url("pullrequests", 7, "comments"))
        .with(query: { "pagelen" => "50" })
        .to_return(json({ "values" => [ COMMENT, COMMENT.merge("id" => 502, "deleted" => true) ] }))

      items, cursor = @api.comments(WS, REPO, 7)

      assert_nil cursor
      assert_equal [ { id: 501, parent_id: 500, author: "Ada Lovelace", body: "Please add a test", path: "app/billing.rb",
                       line: 12, resolved: false, created_on: "2026-10-16T09:12:00.000000+00:00" } ], items
    end

    test "an inline reply carries its path, line and parent" do
      stub = stub_request(:post, repo_url("pullrequests", 7, "comments"))
             .with(body: { content: { raw: "Done" }, inline: { path: "app/billing.rb", to: 12 }, parent: { id: 500 } })
             .to_return(json(COMMENT, status: 201))

      @api.create_comment(WS, REPO, 7, body: "Done", path: "app/billing.rb", line: "12", parent_id: "500")

      assert_requested stub
    end

    test "commit statuses of one commit" do
      stub_request(:get, repo_url("commit", "e3c6ad85c1b5", "statuses"))
        .with(query: { "pagelen" => "100" })
        .to_return(json({ "values" => [ { "type" => "build", "key" => "pipe-1", "name" => "Pipeline #12",
                                         "state" => "INPROGRESS", "url" => "https://bitbucket.org/acme/api/pipelines/12",
                                         "refname" => "feature" } ] }))

      assert_equal [ { key: "pipe-1", name: "Pipeline #12", state: "INPROGRESS",
                       url: "https://bitbucket.org/acme/api/pipelines/12", refname: "feature" } ],
                   @api.commit_statuses(WS, REPO, "e3c6ad85c1b5")
    end

    test "diffstat names the new path, and the old one for a rename" do
      stub_request(:get, repo_url("pullrequests", 7, "diffstat"))
        .with(query: { "pagelen" => "100" })
        .to_return(json({ "values" => [ { "status" => "renamed", "lines_added" => 3, "lines_removed" => 1,
                                         "old" => { "path" => "a.rb" }, "new" => { "path" => "b.rb" } } ] }))

      items, = @api.diffstat(WS, REPO, 7)

      assert_equal [ { path: "b.rb", old_path: "a.rb", status: "renamed", additions: 3, deletions: 1 } ], items
    end

    # R4: the fake answers in the adapter's shapes.
    test "FakeBitbucket::Api answers with the same keys as the adapter" do
      stub_request(:get, repo_url).to_return(json(REPOSITORY))
      stub_request(:get, repo_url("pullrequests", 7)).to_return(json(PULL_REQUEST))
      stub_request(:get, repo_url("pullrequests", 7, "comments")).with(query: hash_including({}))
                                                                .to_return(json({ "values" => [ COMMENT ] }))
      stub_request(:get, "#{BITBUCKET_API}/user").to_return(json({ "uuid" => "{u}", "display_name" => "Ada" }))
      fake = FakeBitbucket::Api.new
      fake.user = { uuid: "{u}", account_id: "x", display_name: "Ada", nickname: "ada" }
      fake.create_comment("acme", "api", 7, body: "x")

      assert_equal @api.repository(WS, REPO).keys.sort, fake.repository("acme", "api").keys.sort
      assert_equal @api.pull_request(WS, REPO, 7).keys.sort, fake.pull_request("acme", "api", 7).keys.sort
      assert_equal @api.comments(WS, REPO, 7).first.first.keys.sort, fake.comments("acme", "api", 7).first.first.keys.sort
      assert_equal @api.current_user.keys.sort, fake.current_user.keys.sort
    end
  end
end
