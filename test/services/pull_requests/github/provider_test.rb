# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Github
    # Contract test: pins the GitHub pull-request adapter against api.github.com
    # through WebMock with realistic payloads. Octokit and Github::TokenService run
    # for real against the stubbed HTTP boundary — only the installation-token
    # endpoint is answered, the way the other GitHub adapter tests do it.
    class ProviderTest < ActiveSupport::TestCase
      include PullRequestsProviderContract

      API = "https://api.github.com"
      REPO = "#{API}/repos/acme/app".freeze
      HEAD = PullRequestsProviderContract::CONTRACT_SHA

      setup do
        @company = create(:company)
        @user = create(:user, :employee, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @integration = create(:integration, :github, :active, company: @company, connected_by: @user, project: @project)
        @integration.credentials_data = { "installation_id" => "12345" }
        @integration.save!
        @repository = create(:repository, integration: @integration, scope: @project, full_name: "acme/app",
                                          clone_url: "https://github.com/acme/app.git")

        @pem_path = Rails.root.join("tmp", "test-github-pull-requests-#{Process.pid}.pem")
        File.write(@pem_path, OpenSSL::PKey::RSA.generate(2048).to_pem)
        Settings.github.stubs(:app_id).returns("999")
        Settings.github.stubs(:app_slug).returns("aixle-flow")
        Settings.github.stubs(:private_key_path).returns(@pem_path.to_s)
        ::Github::TokenService::TOKENS.clear
        @minted = stub_request(:post, "#{API}/app/installations/12345/access_tokens")
                  .to_return(json({ token: "ghs_pull_requests", expires_at: 1.hour.from_now.iso8601 }, status: 201))

        @provider = Provider.new(@integration)
      end

      teardown { FileUtils.rm_f(@pem_path) }

      # == contract hooks ==

      def contract_provider = @provider
      def contract_repository = @repository
      def contract_owned_url(number) = "https://github.com/acme/app/pull/#{number}"

      def arrange_open_pull_request(number:, head_sha:)
        stub_request(:get, "#{REPO}/pulls/#{number}").to_return(json(pr(number, sha: head_sha)))
        stub_request(:get, "#{REPO}/pulls").with(query: hash_including("state" => "open"))
                                         .to_return(json([ pr(number, sha: head_sha) ]))
      end

      def arrange_merged_pull_request(number:)
        stub_request(:get, "#{REPO}/pulls/#{number}").to_return(json(pr(number, merged: true)))
      end

      def arrange_merge_accepted(number:)
        stub_request(:get, "#{REPO}/pulls/#{number}")
          .to_return(json(pr(number))).then.to_return(json(pr(number, merged: true)))
        stub_request(:put, "#{REPO}/pulls/#{number}/merge")
          .to_return(json({ sha: "9" * 40, merged: true, message: "Pull Request successfully merged" }))
      end

      def arrange_comment_created(number:, body:)
        stub_request(:post, "#{API}/repos/acme/app/issues/#{number}/comments")
          .to_return(json(issue_comment(501, body), status: 201))
      end

      def assert_merge_not_attempted(number)
        assert_not_requested :put, "#{REPO}/pulls/#{number}/merge"
      end

      # == credentials ==

      test "an App connection asks for a token narrowed to the one repository" do
        stub_request(:get, "#{REPO}/pulls/7").with(headers: { "Authorization" => /ghs_pull_requests/ })
                                             .to_return(json(pr(7)))

        @provider.get(@repository, 7)

        assert_requested(:post, "#{API}/app/installations/12345/access_tokens") do |request|
          JSON.parse(request.body)["repositories"] == [ "app" ]
        end
      end

      test "a PAT connection uses its own token and mints nothing" do
        pat = create(:integration, :github_pat, :active, company: @company, connected_by: @user, project: @project)
        repository = create(:repository, integration: pat, scope: @project, full_name: "acme/tool",
                                         clone_url: "https://github.com/acme/tool.git")
        stub_request(:get, "#{API}/repos/acme/tool/pulls/3")
          .with(headers: { "Authorization" => /#{pat.github_personal_access_token}/ })
          .to_return(json(pr(3).merge(base: { ref: "main" })))

        assert_equal 3, Provider.new(pat).get(repository, "#3").number
        assert_not_requested :post, "#{API}/app/installations/12345/access_tokens"
      end

      # == reads ==

      test "get maps the pull request and builds its URL from the repository name" do
        stub_request(:get, "#{REPO}/pulls/7")
          .to_return(json(pr(7, draft: true, html_url: "https://evil.example/x", mergeable: false,
                                requested_reviewers: [ { login: "octo-reviewer" } ])))

        pull_request = @provider.get(@repository, "https://github.com/acme/app/pull/7/files")

        assert_equal "https://github.com/acme/app/pull/7", pull_request.url
        assert_equal "open", pull_request.state
        assert pull_request.draft
        assert_equal "feature/login", pull_request.source_branch
        assert_equal "main", pull_request.target_branch
        assert_equal HEAD, pull_request.head_sha
        assert_equal "octocat", pull_request.author
        assert_equal [ "octo-reviewer" ], pull_request.reviewers
        assert_same false, pull_request.mergeable
      end

      test "list filters by the source branch as owner:branch and pages by GitHub's next link" do
        stub = stub_request(:get, "#{REPO}/pulls")
               .with(query: hash_including("state" => "open", "head" => "acme:feature/login", "per_page" => "2", "page" => "1"))
               .to_return(json([ pr(7), pr(8) ], headers: { "Link" => %(<#{REPO}/pulls?page=2>; rel="next") }))

        page = @provider.list(@repository, state: "open", source_branch: "feature/login", cursor: nil, limit: 2)

        assert_requested stub
        assert_equal [ 7, 8 ], page.items.map(&:number)
        assert_equal "2", page.next_cursor
      end

      test "merged and closed are told apart by merged_at, which GitHub's state filter cannot do" do
        stub_request(:get, "#{REPO}/pulls").with(query: hash_including("state" => "closed"))
                                         .to_return(json([ pr(7, merged: true), pr(8, state: "closed") ]))

        merged = @provider.list(@repository, state: "merged", source_branch: nil, cursor: nil, limit: 20)
        closed = @provider.list(@repository, state: "closed", source_branch: nil, cursor: nil, limit: 20)

        assert_equal [ 7 ], merged.items.map(&:number)
        assert_equal [ "merged" ], merged.items.map(&:state)
        assert_equal [ 8 ], closed.items.map(&:number)
      end

      test "changes lists the files with their status and line counts" do
        stub_request(:get, "#{REPO}/pulls/7/files").with(query: hash_including("page" => "1"))
          .to_return(json([
            { filename: "lib/login.rb", status: "modified", additions: 3, deletions: 1 },
            { filename: "lib/session.rb", previous_filename: "lib/old_session.rb", status: "renamed", additions: 0, deletions: 0 },
            { filename: "README.md", status: "added", additions: 10, deletions: 0 }
          ]))

        changes = @provider.changes(@repository, 7, cursor: nil, limit: 50).items

        assert_equal %w[modified renamed added], changes.map(&:status)
        assert_equal "lib/old_session.rb", changes[1].old_path
        assert_equal 3, changes[0].additions
      end

      test "checks combines commit statuses and check runs on the head commit" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/status")
          .to_return(json({ state: "pending", statuses: [ { context: "ci/jenkins", state: "success", target_url: "https://ci.example/1" } ] }))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/check-runs").with(query: hash_including({}))
          .to_return(json({ total_count: 2, check_runs: [
            { name: "lint", status: "completed", conclusion: "success", html_url: "https://github.com/acme/app/runs/1" },
            { name: "tests", status: "in_progress", conclusion: nil, html_url: "https://github.com/acme/app/runs/2" }
          ] }))

        checks = @provider.checks(@repository, 7)

        assert_equal "pending", checks.state
        assert_equal HEAD, checks.head_sha
        assert_equal [ %w[ci/jenkins passed], %w[lint passed], %w[tests pending] ], checks.items.map { |i| [ i[:name], i[:status] ] }
      end

      test "checks report none when nothing has reported on the head, not a pass" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/status").to_return(json({ state: "pending", statuses: [] }))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/check-runs").with(query: hash_including({}))
          .to_return(json({ total_count: 0, check_runs: [] }))

        assert_equal "none", @provider.checks(@repository, 7).state
      end

      test "a failed check run fails the pull request's checks" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/status").to_return(json({ state: "success", statuses: [] }))
        stub_request(:get, "#{REPO}/commits/#{HEAD}/check-runs").with(query: hash_including({}))
          .to_return(json({ total_count: 1, check_runs: [ { name: "tests", status: "completed", conclusion: "timed_out" } ] }))

        assert_equal "failed", @provider.checks(@repository, 7).state
      end

      test "comments merge conversation and inline comments in time order, inline ones keeping their thread" do
        stub_request(:get, "#{API}/repos/acme/app/issues/7/comments").with(query: hash_including("page" => "1"))
          .to_return(json([ issue_comment(501, "Overall fine", at: "2026-10-16T10:00:00Z") ]))
        stub_request(:get, "#{REPO}/pulls/7/comments").with(query: hash_including("page" => "1"))
          .to_return(json([
            review_comment(601, "Rename this", at: "2026-10-16T09:00:00Z"),
            review_comment(602, "Done", at: "2026-10-16T11:00:00Z", in_reply_to_id: 601)
          ]))

        comments = @provider.list_comments(@repository, 7, cursor: nil, limit: 50).items

        assert_equal [ 601, 501, 602 ], comments.map(&:id)
        assert_equal [ "lib/login.rb", nil, "lib/login.rb" ], comments.map(&:file_path)
        assert_equal 601, comments.last.parent_id
        assert_nil comments[1].parent_id
      end

      # == writes ==

      test "create opens a draft from the branch into the target" do
        stub = stub_request(:post, "#{REPO}/pulls")
               .with(body: hash_including("base" => "main", "head" => "feature/login", "title" => "ENG-1: Login", "draft" => true))
               .to_return(json(pr(9, draft: true), status: 201))

        pull_request = @provider.create(@repository, source_branch: "feature/login", target_branch: "main",
                                                     title: "ENG-1: Login", description: "Adds login", draft: true)

        assert_requested stub
        assert_equal 9, pull_request.number
        assert pull_request.draft
      end

      test "update edits the title and marks a draft ready through GraphQL" do
        stub_request(:get, "#{REPO}/pulls/7")
          .to_return(json(pr(7, draft: true))).then.to_return(json(pr(7, draft: false, title: "Better title")))
        patch = stub_request(:patch, "#{REPO}/pulls/7").with(body: hash_including("title" => "Better title"))
                                                      .to_return(json(pr(7, draft: true, title: "Better title")))
        graphql = stub_request(:post, "#{API}/graphql")
                  .with { |request| JSON.parse(request.body)["query"].include?("markPullRequestReadyForReview") }
                  .to_return(json({ data: { markPullRequestReadyForReview: { pullRequest: { isDraft: false } } } }))

        pull_request = @provider.update(@repository, 7, title: "Better title", draft: false)

        assert_requested patch
        assert_requested graphql
        assert_not pull_request.draft
      end

      test "a merged pull request cannot be reopened or retargeted" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7, merged: true)))

        error = assert_raises(PullRequests::Error) { @provider.update(@repository, 7, state: "open") }

        assert_equal "conflict", error.code
      end

      test "an inline comment is placed on the head commit's line" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub = stub_request(:post, "#{REPO}/pulls/7/comments")
               .with(body: hash_including("commit_id" => HEAD, "path" => "lib/login.rb", "line" => 12, "side" => "RIGHT"))
               .to_return(json(review_comment(603, "Nit"), status: 201))

        comment = @provider.add_comment(@repository, 7, body: "Nit", file_path: "lib/login.rb", line: 12, reply_to: nil)

        assert_requested stub
        assert_equal "lib/login.rb", comment.file_path
      end

      test "a reply to an inline comment lands in its thread" do
        stub_request(:get, "#{REPO}/pulls/comments/601").to_return(json(review_comment(601, "Rename this")))
        stub = stub_request(:post, "#{REPO}/pulls/7/comments").with(body: hash_including("in_reply_to" => 601))
                                                             .to_return(json(review_comment(604, "Renamed", in_reply_to_id: 601), status: 201))

        comment = @provider.add_comment(@repository, 7, body: "Renamed", file_path: nil, line: nil, reply_to: 601)

        assert_requested stub
        assert_equal 601, comment.parent_id
      end

      test "a reply to a conversation comment is a new conversation comment" do
        stub_request(:get, "#{REPO}/pulls/comments/501").to_return(status: 404, headers: { "Content-Type" => "application/json" },
                                                                    body: { message: "Not Found" }.to_json)
        stub = stub_request(:post, "#{API}/repos/acme/app/issues/7/comments").to_return(json(issue_comment(502, "Agreed"), status: 201))

        comment = @provider.add_comment(@repository, 7, body: "Agreed", file_path: nil, line: nil, reply_to: 501)

        assert_requested stub
        assert_nil comment.parent_id
      end

      test "request_changes always carries a body, as GitHub requires" do
        stub = stub_request(:post, "#{REPO}/pulls/7/reviews")
               .with(body: hash_including("event" => "REQUEST_CHANGES", "body" => "Changes requested."))
               .to_return(json(review(801, "CHANGES_REQUESTED")))

        result = @provider.review(@repository, 7, verdict: "request_changes", body: nil)

        assert_requested stub
        assert_equal "request_changes", result.verdict
        assert_equal "aixle-flow[bot]", result.reviewer
      end

      test "GitHub refusing a review of your own pull request is a permission refusal, not bad input" do
        stub_request(:post, "#{REPO}/pulls/7/reviews")
          .to_return(status: 422, headers: { "Content-Type" => "application/json" },
                     body: { message: "Unprocessable Entity", errors: [ "Can not approve your own pull request" ] }.to_json)

        error = assert_raises(PullRequests::Error) { @provider.review(@repository, 7, verdict: "approve", body: nil) }

        assert_equal "permission_denied", error.code
      end

      test "unapprove dismisses this connection's latest approval" do
        stub_request(:get, "#{REPO}/pulls/7/reviews").with(query: hash_including({}))
          .to_return(json([ review(801, "APPROVED"), review(802, "APPROVED", login: "someone-else") ]))
        dismiss = stub_request(:put, "#{REPO}/pulls/7/reviews/801/dismissals").to_return(json(review(801, "DISMISSED")))

        @provider.review(@repository, 7, verdict: "unapprove", body: nil)

        assert_requested dismiss
      end

      test "a merge sends GitHub the reviewed head, the method, and deletes the branch afterwards" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7))).then.to_return(json(pr(7, merged: true)))
        merge = stub_request(:put, "#{REPO}/pulls/7/merge")
                .with(body: hash_including("sha" => HEAD, "merge_method" => "squash", "commit_message" => "Squashed"))
                .to_return(json({ sha: "9" * 40, merged: true, message: "Pull Request successfully merged" }))
        delete = stub_request(:delete, "#{REPO}/git/refs/heads/feature/login").to_return(status: 204)

        result = @provider.merge(@repository, 7, expected_head_sha: HEAD[0, 12], strategy: "squash",
                                                 delete_source_branch: true, message: "Squashed")

        assert_requested merge
        assert_requested delete
        assert result.merged
      end

      test "GitHub's own head guard firing is a conflict" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub_request(:put, "#{REPO}/pulls/7/merge")
          .to_return(status: 409, headers: { "Content-Type" => "application/json" },
                     body: { message: "Head branch was modified. Review and try the merge again." }.to_json)

        error = assert_raises(PullRequests::Error) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: nil, delete_source_branch: false, message: nil)
        end

        assert_equal "conflict", error.code
      end

      test "a pull request GitHub will not merge now is not_mergeable" do
        stub_request(:get, "#{REPO}/pulls/7").to_return(json(pr(7)))
        stub_request(:put, "#{REPO}/pulls/7/merge")
          .to_return(status: 405, headers: { "Content-Type" => "application/json" },
                     body: { message: "Required status check \"tests\" is expected." }.to_json)

        error = assert_raises(PullRequests::Error) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: "merge_commit", delete_source_branch: false, message: nil)
        end

        assert_equal "not_mergeable", error.code
        assert_includes error.message, "Required status check"
      end

      # == errors ==

      test "a write GitHub never answered is an unknown outcome" do
        stub_request(:post, "#{REPO}/pulls").to_return(status: 502, body: "")

        error = assert_raises(PullRequests::Error) do
          @provider.create(@repository, source_branch: "feature/login", target_branch: "main", title: "x", draft: true)
        end

        assert_equal "outcome_unknown", error.code
      end

      test "a rate limit is reported as such" do
        stub_request(:get, "#{REPO}/pulls/7")
          .to_return(status: 403, headers: { "Content-Type" => "application/json", "X-RateLimit-Remaining" => "0" },
                     body: { message: "API rate limit exceeded for installation ID 12345." }.to_json)

        error = assert_raises(PullRequests::Error) { @provider.get(@repository, 7) }

        assert_equal "rate_limited", error.code
      end

      test "a pull request this connection cannot see is not found" do
        stub_request(:get, "#{REPO}/pulls/7")
          .to_return(status: 404, headers: { "Content-Type" => "application/json" }, body: { message: "Not Found" }.to_json)

        error = assert_raises(PullRequests::Error) { @provider.get(@repository, 7) }

        assert_equal "not_found_or_inaccessible", error.code
      end

      test "owns_reference? accepts only this repository's pull request URLs" do
        assert @provider.owns_reference?(@repository, "https://github.com/acme/app/pull/7")
        assert_not @provider.owns_reference?(@repository, "https://github.com/acme/other/pull/7")
        assert_not @provider.owns_reference?(@repository, "https://github.com/acme/app/issues/7")
      end

      private

      def json(body, status: 200, headers: {})
        { status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: body.to_json }
      end

      def pr(number, sha: HEAD, state: "open", merged: false, draft: false, title: "Add login", **extra)
        {
          id: 1_000 + number, node_id: "PR_kwDO#{number}", number: number, state: merged ? "closed" : state,
          title: title, body: "Adds a login form", draft: draft, merged: merged,
          merged_at: (merged ? "2026-10-16T12:00:00Z" : nil), mergeable: true,
          html_url: "https://github.com/acme/app/pull/#{number}", user: { login: "octocat" }, requested_reviewers: [],
          head: { ref: "feature/login", sha: sha, repo: { full_name: "acme/app" } },
          base: { ref: "main", sha: "b" * 40, repo: { full_name: "acme/app" } },
          created_at: "2026-10-16T08:00:00Z", updated_at: "2026-10-16T09:00:00Z"
        }.merge(extra)
      end

      def issue_comment(id, body, at: "2026-10-16T10:00:00Z")
        { id: id, body: body, user: { login: "octocat" }, created_at: at, updated_at: at,
          html_url: "https://github.com/acme/app/pull/7#issuecomment-#{id}" }
      end

      def review_comment(id, body, at: "2026-10-16T10:00:00Z", in_reply_to_id: nil)
        { id: id, body: body, user: { login: "octocat" }, path: "lib/login.rb", line: 12, original_line: 12,
          commit_id: HEAD, in_reply_to_id: in_reply_to_id, created_at: at, updated_at: at,
          pull_request_url: "#{REPO}/pulls/7" }.compact
      end

      def review(id, state, login: "aixle-flow[bot]")
        { id: id, state: state, body: "", user: { login: login }, submitted_at: "2026-10-16T12:00:00Z", commit_id: HEAD }
      end
    end
  end
end
