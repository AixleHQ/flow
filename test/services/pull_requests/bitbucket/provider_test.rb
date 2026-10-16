# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Bitbucket
    class ProviderTest < ActiveSupport::TestCase
      HEAD = FakeBitbucket::Api::HEAD
      UUID = FakeBitbucket::Api::REPOSITORY_UUID

      setup do
        with_bitbucket_settings
        @bitbucket = stub_bitbucket!
        @integration = create(:integration, :bitbucket, :active)
        @repository = create(:repository, :bitbucket, integration: @integration, full_name: "acme/api", external_id: UUID)
        @provider = PullRequests::Provider.for(@integration)
      end

      test "the registry hands out this adapter for a Bitbucket connection" do
        assert_instance_of Provider, @provider
      end

      test "reads a pull request by the repository's UUIDs, as the port's value" do
        pr = @provider.get(@repository, "https://bitbucket.org/acme/api/pull-requests/7/diff")

        assert_equal 7, pr.number
        assert_equal "https://bitbucket.org/acme/api/pull-requests/7", pr.url
        assert_equal "open", pr.state
        assert_equal "feature", pr.source_branch
        assert_equal "main", pr.target_branch
        assert_equal HEAD, pr.head_sha
        call = @bitbucket.calls_to(:pull_request).last
        assert_equal [ FakeBitbucket::Api::WORKSPACE_UUID, UUID ], [ call[:workspace], call[:repository] ]
      end

      test "a URL of another repository is not a reference to this one" do
        assert_not @provider.owns_reference?(@repository, "https://bitbucket.org/acme/other/pull-requests/7")
        error = assert_raises(Error) { @provider.get(@repository, "https://bitbucket.org/acme/other/pull-requests/7") }
        assert_equal "validation_failed", error.code
      end

      test "lists by state and source branch" do
        @bitbucket.add_pull_request(UUID, id: 8, title: "Old", source_branch: "old", state: "DECLINED")

        assert_equal [ 7 ], @provider.list(@repository, source_branch: "feature").items.map(&:number)
        assert_equal [ 8 ], @provider.list(@repository, state: "closed").items.map(&:number)
        assert_raises(Error) { @provider.list(@repository, state: "weird") }
      end

      test "creates a draft pull request" do
        pr = @provider.create(@repository, source_branch: "fix", target_branch: "main", title: "Fix", description: "Why",
                                           draft: true)

        assert pr.draft
        assert_equal "fix", pr.source_branch
        assert_equal "Why", pr.description
      end

      test "updates fields, keeps the title when not given, and declines to close" do
        pr = @provider.update(@repository, 7, description: "New body")
        assert_equal "Add billing", pr.title
        assert_equal "New body", pr.description

        closed = @provider.update(@repository, 7, state: "closed")
        assert_equal "closed", closed.state
        error = assert_raises(Error::Conflict) { @provider.update(@repository, 7, state: "open") }
        assert_equal({ state: "closed" }, error.details)
      end

      test "comments inline and in reply" do
        comment = @provider.add_comment(@repository, 7, body: "Here", file_path: "app/billing.rb", line: 12, reply_to: "500")

        assert_equal [ "app/billing.rb", 12, 500 ], [ comment.file_path, comment.line, comment.parent_id ]
        assert_equal [ comment.id ], @provider.list_comments(@repository, 7).items.map(&:id)
        assert_raises(Error) { @provider.add_comment(@repository, 7, body: "x", file_path: "a.rb") }
      end

      test "reviews approve, unapprove and request changes, with a comment when given" do
        assert_equal "approve", @provider.review(@repository, 7, verdict: "approve").verdict
        @provider.review(@repository, 7, verdict: "unapprove")
        @provider.review(@repository, 7, verdict: "request_changes", body: "Needs a test")

        assert @bitbucket.called?(:approve)
        assert @bitbucket.called?(:unapprove)
        assert @bitbucket.called?(:request_changes)
        assert_equal "Needs a test", @bitbucket.calls_to(:create_comment).last[:body]
      end

      test "merges only the head that was reviewed, matching a full SHA against Bitbucket's short one" do
        result = @provider.merge(@repository, 7, expected_head_sha: "#{HEAD}abcdef0123456789abcdef0123", strategy: "squash",
                                                 delete_source_branch: true)

        assert result.merged
        assert_not result.already_merged
        assert_equal "merged", result.pull_request.state
        call = @bitbucket.calls_to(:merge_pull_request).last
        assert_equal [ "squash", true ], [ call[:strategy], call[:close_source_branch] ]
      end

      test "a moved head is a conflict and nothing is merged" do
        error = assert_raises(Error::Conflict) { @provider.merge(@repository, 7, expected_head_sha: "0000000000000000") }

        assert_equal HEAD, error.details[:current_head_sha]
        assert_not @bitbucket.called?(:merge_pull_request)
      end

      test "an already merged pull request says so instead of merging again" do
        @bitbucket.pull_request_store[UUID][7][:state] = "MERGED"

        result = @provider.merge(@repository, 7, expected_head_sha: HEAD)

        assert result.already_merged
        assert_not @bitbucket.called?(:merge_pull_request)
      end

      test "a merge Bitbucket queues and has not finished is reported pending" do
        @bitbucket.merge_mode = :async

        result = @provider.merge(@repository, 7, expected_head_sha: HEAD)

        assert result.pending
        assert_not result.merged
        assert_equal 3, @bitbucket.calls_to(:merge_task).size
      end

      test "a merge Bitbucket refuses as things stand is not_mergeable, an unknown outcome stays unknown" do
        @bitbucket.fail_on(:merge_pull_request, ::Bitbucket::Error::ValidationFailed.new("needs 2 approvals"))
        assert_equal "not_mergeable", assert_raises(Error) { @provider.merge(@repository, 7, expected_head_sha: HEAD) }.code

        @bitbucket.fail_on(:merge_pull_request, ::Bitbucket::Error::OutcomeUnknown.new("timeout"))
        assert_raises(Error::OutcomeUnknown) { @provider.merge(@repository, 7, expected_head_sha: HEAD) }
      end

      test "an unknown strategy is refused before anything is sent" do
        assert_raises(Error) { @provider.merge(@repository, 7, expected_head_sha: HEAD, strategy: "octopus") }
        assert_not @bitbucket.called?(:merge_pull_request)
      end

      test "checks summarise the head commit's statuses" do
        assert_equal "none", @provider.checks(@repository, 7).state

        @bitbucket.add_status(HEAD, state: "INPROGRESS")
        assert_equal "pending", @provider.checks(@repository, 7).state

        @bitbucket.add_status(HEAD, state: "FAILED")
        checks = @provider.checks(@repository, 7)
        assert_equal "failed", checks.state
        assert_equal HEAD, checks.head_sha
        assert_equal %w[pending failed], checks.items.map { |item| item[:status] }
      end

      test "changes come from the diffstat" do
        change = @provider.changes(@repository, 7).items.first

        assert_equal [ "app/billing.rb", "added", 12 ], [ change.path, change.status, change.additions ]
      end

      test "a repository without its Bitbucket identity is refused rather than addressed by name" do
        @repository.external_id = nil

        assert_raises(Error) { @provider.get(@repository, 7) }
      end
    end
  end
end
