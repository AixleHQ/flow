# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Gitlab
    # Contract test: pins the GitLab pull-request adapter against GitLab's REST
    # API through WebMock with realistic payloads. The real gem client and
    # ::Gitlab::TokenService run against the stubbed HTTP boundary — nothing of
    # the gem is mocked (testing doctrine R2/R4).
    class ProviderTest < ActiveSupport::TestCase
      include PullRequestsProviderContract

      GITLAB_API = "https://gitlab.com/api/v4"
      MR = %r{\A#{Regexp.escape(GITLAB_API)}/projects/group(?:%2F|/)app/merge_requests}
      HEAD = PullRequestsProviderContract::CONTRACT_SHA

      setup do
        Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: GITLAB_API))
        @company = create(:company)
        @user = create(:user, :employee, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user, project: @project,
                                                             settings: { "gitlab_username" => "aixle-bot" })
        @repository = create(:repository, integration: @integration, scope: @project, full_name: "group/app",
                                          clone_url: "https://gitlab.com/group/app.git")
        @provider = Provider.new(@integration)
      end

      # == contract hooks ==

      def contract_provider = @provider
      def contract_repository = @repository
      def contract_owned_url(number) = "https://gitlab.com/group/app/-/merge_requests/#{number}"

      def arrange_open_pull_request(number:, head_sha:)
        stub_mr(number, mr(number, sha: head_sha))
        stub_request(:get, mr_url).with(query: hash_including("state" => "opened"))
                                  .to_return(json([ mr(number, sha: head_sha) ]))
      end

      def arrange_merged_pull_request(number:)
        stub_mr(number, mr(number, state: "merged"))
      end

      def arrange_merge_accepted(number:)
        stub_request(:put, mr_url(number, "merge")).to_return(json(mr(number, state: "merged")))
      end

      def arrange_comment_created(number:, body:)
        stub_request(:post, mr_url(number, "discussions"))
          .to_return(json(discussion("d1", [ note(901, body) ]), status: 201))
      end

      def assert_merge_not_attempted(number)
        assert_not_requested :put, mr_url(number, "merge")
      end

      # == reads ==

      test "list asks for opened merge requests of a branch and pages by GitLab's next link" do
        stub = stub_request(:get, mr_url)
               .with(query: hash_including("state" => "opened", "source_branch" => "feature/login", "per_page" => "2",
                                           "page" => "1"))
               .to_return(json([ mr(7), mr(8, title: "Draft: Spike") ],
                               headers: { "Link" => %(<#{GITLAB_API}/projects/group%2Fapp/merge_requests?page=2&per_page=2>; rel="next") }))

        page = @provider.list(@repository, state: "open", source_branch: "feature/login", cursor: nil, limit: 2)

        assert_requested stub
        assert_equal [ 7, 8 ], page.items.map(&:number)
        assert_equal "2", page.next_cursor
        assert_equal "Spike", page.items.last.title
        assert page.items.last.draft
      end

      test "get maps the merge request and builds its URL from the configured host" do
        stub_mr(7, mr(7, web_url: "https://evil.example/x", detailed_merge_status: "ci_still_running"))

        pull_request = @provider.get(@repository, "!7")

        assert_equal "https://gitlab.com/group/app/-/merge_requests/7", pull_request.url
        assert_equal "alice", pull_request.author
        assert_equal [ "bob" ], pull_request.reviewers
        assert_equal false, pull_request.mergeable # rubocop:disable Minitest/RefuteFalse
        assert_equal "feature/login", pull_request.source_branch
      end

      test "a merge request GitLab is still checking has no mergeability verdict yet" do
        stub_mr(7, mr(7, detailed_merge_status: "checking"))

        assert_nil @provider.get(@repository, 7).mergeable
      end

      test "a merge request of another repository cannot be named by its URL" do
        error = assert_raises(PullRequests::Error) do
          @provider.get(@repository, "https://gitlab.com/group/other/-/merge_requests/7")
        end

        assert_equal "validation_failed", error.code
      end

      test "changes lists files with their status and line counts" do
        stub_request(:get, mr_url(7, "diffs")).with(query: hash_including("page" => "1"))
                                              .to_return(json([
                                                diff("app/a.rb", diff: "@@ -1 +1,2 @@\n-old\n+new\n+more\n"),
                                                diff("app/b.rb", new_file: true, diff: "+x\n"),
                                                diff("app/c.rb", old_path: "app/old_c.rb", renamed_file: true, diff: "")
                                              ]))

        files = @provider.changes(@repository, 7, cursor: nil, limit: 50).items

        assert_equal %w[modified added renamed], files.map(&:status)
        assert_equal [ 2, 1 ], [ files.first.additions, files.first.deletions ]
        assert_equal "app/old_c.rb", files.last.old_path
      end

      test "list_comments flattens threads, drops system notes and marks replies" do
        stub_request(:get, mr_url(7, "discussions")).with(query: hash_including("page" => "1"))
                                                    .to_return(json([
                                                      discussion("d1", [ note(1, "Why?", position: true), note(2, "Because") ]),
                                                      discussion("d2", [ note(3, "added 1 commit", system: true) ])
                                                    ]))

        comments = @provider.list_comments(@repository, 7, cursor: nil, limit: 50).items

        assert_equal [ 1, 2 ], comments.map(&:id)
        assert_nil comments.first.parent_id
        assert_equal 1, comments.last.parent_id
        assert_equal [ "app/a.rb", 12 ], [ comments.first.file_path, comments.first.line ]
      end

      test "checks report the head pipeline and every commit status" do
        stub_mr(7, mr(7, head_pipeline: { id: 555, status: "running" }))
        stub_request(:get, %r{#{Regexp.escape(GITLAB_API)}/projects/group(?:%2F|/)app/repository/commits/#{HEAD}/statuses})
          .to_return(json([ status("lint", "success"), status("rspec", "running"), status("flaky", "failed", allow_failure: true) ]))

        checks = @provider.checks(@repository, 7)

        assert_equal "pending", checks.state
        assert_equal HEAD, checks.head_sha
        assert_equal %w[passed pending passed], checks.items.map { |item| item[:status] }
      end

      test "checks are none when nothing reported" do
        stub_mr(7, mr(7, head_pipeline: nil))
        stub_request(:get, %r{/repository/commits/#{HEAD}/statuses}).to_return(json([]))

        assert_equal "none", @provider.checks(@repository, 7).state
      end

      # == writes ==

      test "create opens a draft through GitLab's Draft: title prefix" do
        stub = stub_request(:post, mr_url)
               .with(body: hash_including("title" => "Draft: Add login", "source_branch" => "feature/login",
                                          "target_branch" => "main"))
               .to_return(json(mr(7, title: "Draft: Add login", draft: true), status: 201))

        pull_request = @provider.create(@repository, source_branch: "feature/login", target_branch: "main",
                                                     title: "Add login", description: nil, draft: true)

        assert_requested stub
        assert pull_request.draft
        assert_equal "Add login", pull_request.title
      end

      test "update closes through state_event and keeps the draft prefix when the title changes" do
        stub_mr(7, mr(7, title: "Draft: Old"))
        stub = stub_request(:put, mr_url(7))
               .with(body: hash_including("title" => "Draft: New", "state_event" => "close"))
               .to_return(json(mr(7, title: "Draft: New", state: "closed")))

        pull_request = @provider.update(@repository, 7, title: "New", state: "closed")

        assert_requested stub
        assert_equal "closed", pull_request.state
      end

      test "an inline comment is positioned on the merge request's diff refs" do
        stub_mr(7, mr(7))
        stub = stub_request(:post, mr_url(7, "discussions"))
               .with { |request| request.body.include?("position%5Bnew_path%5D=app%2Fa.rb") && request.body.include?("position%5Bbase_sha%5D=base000") }
               .to_return(json(discussion("d9", [ note(77, "Nit", position: true) ]), status: 201))

        comment = @provider.add_comment(@repository, 7, body: "Nit", file_path: "app/a.rb", line: 12, reply_to: nil)

        assert_requested stub
        assert_equal 77, comment.id
      end

      test "a reply lands in the thread holding the comment it answers" do
        stub_request(:get, mr_url(7, "discussions")).with(query: hash_including("per_page" => "100"))
                                                    .to_return(json([ discussion("abc123", [ note(1, "Why?"), note(2, "Hm") ]) ]))
        stub = stub_request(:post, mr_url(7, "discussions/abc123/notes")).to_return(json(note(3, "Because"), status: 201))

        comment = @provider.add_comment(@repository, 7, body: "Because", file_path: nil, line: nil, reply_to: "2")

        assert_requested stub
        assert_equal 1, comment.parent_id
      end

      test "an approval GitLab will not take is a permission problem, not a revoked token" do
        stub_request(:post, mr_url(7, "approve")).to_return(json({ message: "401 Unauthorized" }, status: 401))

        error = assert_raises(PullRequests::Error) { @provider.review(@repository, 7, verdict: "approve", body: nil) }

        assert_equal "permission_denied", error.code
      end

      test "approve answers the connection's account as the reviewer" do
        stub_request(:post, mr_url(7, "approve")).to_return(json({ id: 9001, iid: 7, approved_by: [] }, status: 201))

        review = @provider.review(@repository, 7, verdict: "approve", body: nil)

        assert_equal [ "aixle-bot", "approve" ], [ review.reviewer, review.verdict ]
      end

      test "request_changes is not a GitLab review state" do
        error = assert_raises(PullRequests::Error) { @provider.review(@repository, 7, verdict: "request_changes", body: nil) }

        assert_equal "unsupported", error.code
      end

      test "a merge sends GitLab its own sha guard and the squash choice" do
        stub_mr(7, mr(7))
        stub = stub_request(:put, mr_url(7, "merge"))
               .with(body: hash_including("sha" => HEAD, "squash" => "true", "should_remove_source_branch" => "true"))
               .to_return(json(mr(7, state: "merged")))

        result = @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: "squash", delete_source_branch: true,
                                                 message: nil)

        assert_requested stub
        assert result.merged
      end

      test "GitLab's own sha guard firing is a conflict" do
        stub_mr(7, mr(7))
        stub_request(:put, mr_url(7, "merge")).to_return(json({ message: "SHA does not match HEAD of source branch" }, status: 409))

        error = assert_raises(PullRequests::Error) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: nil, delete_source_branch: false, message: nil)
        end

        assert_equal "conflict", error.code
      end

      test "a merge request GitLab will not merge yet says why" do
        stub_mr(7, mr(7))
        stub_request(:put, mr_url(7, "merge")).to_return(json({ message: "405 Method Not Allowed" }, status: 405))

        error = assert_raises(PullRequests::Error) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: nil, delete_source_branch: false, message: nil)
        end

        assert_equal "not_mergeable", error.code
        assert_match "405 Method Not Allowed", error.message
      end

      test "a merge that times out is an unknown outcome, never a failure" do
        stub_mr(7, mr(7))
        stub_request(:put, mr_url(7, "merge")).to_timeout

        assert_raises(PullRequests::Error::OutcomeUnknown) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: nil, delete_source_branch: false, message: nil)
        end
      end

      test "fast_forward is the project's merge method to choose, not the call's" do
        stub_mr(7, mr(7))

        error = assert_raises(PullRequests::Error) do
          @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: "fast_forward", delete_source_branch: false,
                                          message: nil)
        end

        assert_equal "unsupported", error.code
      end

      # == errors ==

      test "a merge request GitLab hides or lacks is one code" do
        stub_request(:get, mr_url(7)).to_return(json({ message: "404 Not found" }, status: 404))

        error = assert_raises(PullRequests::Error) { @provider.get(@repository, 7) }

        assert_equal "not_found_or_inaccessible", error.code
      end

      test "a revoked token is not_authorized" do
        stub_request(:get, mr_url(7)).to_return(json({ message: "401 Unauthorized" }, status: 401))

        error = assert_raises(PullRequests::Error) { @provider.get(@repository, 7) }

        assert_equal "not_authorized", error.code
      end

      private

      def mr_url(number = nil, suffix = nil)
        tail = [ number, suffix ].compact.join("/")
        tail.present? ? %r{#{MR.source}/#{tail}(?:\z|\?)} : %r{#{MR.source}(?:\z|\?)}
      end

      def stub_mr(number, body)
        stub_request(:get, mr_url(number)).to_return(json(body))
      end

      def json(body, status: 200, headers: {})
        { status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: body.to_json }
      end

      def mr(iid, state: "opened", title: "Add login", sha: HEAD, draft: false, **overrides)
        {
          id: 9000 + iid, iid: iid, project_id: 278_964, title: title, description: "Adds the login page",
          state: state, created_at: "2026-10-10T08:00:00.000Z", updated_at: "2026-10-11T09:30:00.000Z",
          target_branch: "main", source_branch: "feature/login",
          author: { id: 152, username: "alice", name: "Alice Smith" },
          reviewers: [ { id: 153, username: "bob", name: "Bob Jones" } ],
          draft: draft, work_in_progress: draft, merge_status: "can_be_merged",
          detailed_merge_status: state == "opened" ? "mergeable" : "not_open", sha: sha, merge_commit_sha: nil,
          web_url: "https://gitlab.com/group/app/-/merge_requests/#{iid}",
          diff_refs: { base_sha: "base000", head_sha: sha, start_sha: "start000" },
          head_pipeline: { id: 555, status: "success", web_url: "https://gitlab.com/group/app/-/pipelines/555" }
        }.merge(overrides)
      end

      def discussion(id, notes)
        { id: id, individual_note: notes.one?, notes: notes }
      end

      def note(id, body, system: false, position: false)
        {
          id: id, type: position ? "DiffNote" : "DiscussionNote", body: body, system: system,
          author: { id: 152, username: "alice", name: "Alice Smith" }, created_at: "2026-10-11T10:00:00.000Z",
          resolvable: true, resolved: false,
          position: (position ? { base_sha: "base000", head_sha: HEAD, start_sha: "start000", position_type: "text",
                                  old_path: "app/a.rb", new_path: "app/a.rb", old_line: nil, new_line: 12 } : nil)
        }
      end

      def diff(path, old_path: nil, new_file: false, renamed_file: false, deleted_file: false, diff: "")
        { old_path: old_path || path, new_path: path, a_mode: "100644", b_mode: "100644", diff: diff,
          new_file: new_file, renamed_file: renamed_file, deleted_file: deleted_file }
      end

      def status(name, state, allow_failure: false)
        { id: rand(1000), sha: HEAD, ref: "feature/login", status: state, name: name, allow_failure: allow_failure,
          target_url: "https://gitlab.com/group/app/-/jobs/#{rand(1000)}", created_at: "2026-10-11T10:00:00.000Z" }
      end
    end
  end
end
