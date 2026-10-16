# frozen_string_literal: true

# Assertions every PullRequests::Provider must satisfy — the real adapters
# against their HTTP boundary and Fakes::FakePullRequests in memory — so the fake
# the tool tests run on cannot drift from what the adapters actually do (R4).
#
# An including test defines `contract_provider`, `contract_repository`,
# `contract_owned_url(number)` and the arrangement hooks below, which make the
# host answer as described (WebMock stubs for an adapter, seeded state for the fake).
module PullRequestsProviderContract
  CONTRACT_SHA = "0f3a9c2e5b7d1f4a6c8e0b2d4f6a8c0e2b4d6f8a"

  def self.included(base)
    base.class_eval do
      test "contract: get reads an open pull request with its head commit" do
        arrange_open_pull_request(number: 7, head_sha: CONTRACT_SHA)

        pull_request = contract_provider.get(contract_repository, "7")

        assert_kind_of PullRequests::PullRequest, pull_request
        assert_equal 7, pull_request.number
        assert_equal "open", pull_request.state
        assert_equal CONTRACT_SHA, pull_request.head_sha
        assert_match %r{\Ahttps://}, pull_request.url
        assert contract_provider.owns_reference?(contract_repository, pull_request.url)
      end

      test "contract: a pull request URL resolves to its number, anything else is refused" do
        assert_equal 7, contract_provider.number_of(contract_repository, contract_owned_url(7))

        error = assert_raises(PullRequests::Error) do
          contract_provider.number_of(contract_repository, "https://elsewhere.example/x/pull/7")
        end
        assert_equal "validation_failed", error.code
      end

      test "contract: a merge refuses a head that moved since review, and sends nothing" do
        arrange_open_pull_request(number: 7, head_sha: CONTRACT_SHA)

        error = assert_raises(PullRequests::Error) do
          contract_provider.merge(contract_repository, 7, expected_head_sha: "a" * 40, strategy: nil,
                                                          delete_source_branch: false, message: nil)
        end

        assert_equal "conflict", error.code
        assert_equal CONTRACT_SHA, error.details[:current_head_sha]
        assert_equal "a" * 40, error.details[:expected_head_sha]
        assert_merge_not_attempted(7)
      end

      test "contract: merging a merged pull request reports it and sends nothing" do
        arrange_merged_pull_request(number: 7)

        result = contract_provider.merge(contract_repository, 7, expected_head_sha: CONTRACT_SHA, strategy: nil,
                                                                 delete_source_branch: false, message: nil)

        assert_kind_of PullRequests::MergeResult, result
        assert result.merged
        assert result.already_merged
        assert_merge_not_attempted(7)
      end

      test "contract: a merge at the reviewed head merges" do
        arrange_open_pull_request(number: 7, head_sha: CONTRACT_SHA)
        arrange_merge_accepted(number: 7)

        result = contract_provider.merge(contract_repository, 7, expected_head_sha: CONTRACT_SHA, strategy: nil,
                                                                 delete_source_branch: false, message: nil)

        assert result.merged
        assert_not result.already_merged
        assert_not result.pending
        assert_equal "merged", result.pull_request.state
      end

      test "contract: a comment comes back as a Comment with its body" do
        arrange_open_pull_request(number: 7, head_sha: CONTRACT_SHA)
        arrange_comment_created(number: 7, body: "Looks good")

        comment = contract_provider.add_comment(contract_repository, 7, body: "Looks good", file_path: nil, line: nil,
                                                                        reply_to: nil)

        assert_kind_of PullRequests::Comment, comment
        assert_equal "Looks good", comment.body
        assert comment.id.present?
      end

      test "contract: list answers a Page of pull requests" do
        arrange_open_pull_request(number: 7, head_sha: CONTRACT_SHA)

        page = contract_provider.list(contract_repository, state: "open", source_branch: nil, cursor: nil, limit: 20)

        assert_kind_of PullRequests::Page, page
        assert_equal [ 7 ], page.items.map(&:number)
      end
    end
  end
end
