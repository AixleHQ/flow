# frozen_string_literal: true

require "test_helper"

module Bitbucket
  class CheckStatusServiceTest < ActiveSupport::TestCase
    HEAD = FakeBitbucket::Api::HEAD

    setup do
      with_bitbucket_settings
      @bitbucket = stub_bitbucket!
      @integration = create(:integration, :bitbucket, :active)
      @repository = create(:repository, :bitbucket, integration: @integration, full_name: "acme/api",
                                                    external_id: FakeBitbucket::Api::REPOSITORY_UUID)
      @service = CheckStatusService.new(@integration)
    end

    def probe(expected_commit: nil) = @service.pull_request_statuses(@repository, 7, expected_commit: expected_commit)

    test "no status yet is still in progress" do
      assert probe.in_progress?
    end

    test "waits while any status runs" do
      @bitbucket.add_status(HEAD, state: "SUCCESSFUL", name: "lint")
      @bitbucket.add_status(HEAD, state: "INPROGRESS", name: "tests")

      result = probe
      assert result.in_progress?
      assert_match(%r{1/2 statuses still running}, result.detail)
    end

    test "every status successful is a pass" do
      @bitbucket.add_status(HEAD, state: "SUCCESSFUL")

      result = probe
      assert result.completed?
      assert_equal "successful", result.conclusion
    end

    test "a failed or stopped status fails the gate" do
      @bitbucket.add_status(HEAD, state: "SUCCESSFUL")
      @bitbucket.add_status(HEAD, state: "STOPPED")

      assert_equal "failed", probe.conclusion
    end

    test "a full SHA matches Bitbucket's abbreviated head, a different commit does not" do
      @bitbucket.add_status(HEAD, state: "SUCCESSFUL")

      assert probe(expected_commit: "#{HEAD}0123456789abcdef0123456789").completed?
      assert probe(expected_commit: "0000000000000000").in_progress?
    end

    test "a pull request that is gone is unresolvable, a transient failure is not" do
      @repository.update_columns(external_id: "{00000000-0000-4000-8000-000000000001}")
      assert probe.unresolvable?

      @repository.update_columns(external_id: FakeBitbucket::Api::REPOSITORY_UUID)
      @bitbucket.fail_on(:pull_request, Error::RateLimited.new("slow down"))
      assert probe.unavailable?
    end
  end
end
