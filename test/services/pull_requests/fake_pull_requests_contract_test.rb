# frozen_string_literal: true

require "test_helper"

# The fake the pull_request_* tool tests run on, held to the same contract the
# real adapters satisfy (testing doctrine R4).
class PullRequests::FakePullRequestsContractTest < ActiveSupport::TestCase
  include PullRequestsProviderContract

  setup do
    @repository = create(:repository, :bitbucket)
    @fake = Fakes::FakePullRequests.new
  end

  def contract_provider = @fake
  def contract_repository = @repository
  def contract_owned_url(number) = "#{@fake.url_base(@repository)}/#{number}"

  def arrange_open_pull_request(number:, head_sha:)
    @fake.add_pull_request(@repository, number: number, head_sha: head_sha)
  end

  def arrange_merged_pull_request(number:)
    @fake.add_pull_request(@repository, number: number, state: "merged")
  end

  def arrange_merge_accepted(number:) = nil
  def arrange_comment_created(number:, body:) = nil

  def assert_merge_not_attempted(_number)
    assert_not @fake.called?(:merge)
  end
end
