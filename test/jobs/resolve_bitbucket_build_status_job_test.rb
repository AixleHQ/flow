# frozen_string_literal: true

require "test_helper"

class ResolveBitbucketBuildStatusJobTest < ActiveJob::TestCase
  test "hands the repository and commit to the gate service" do
    GateService.expects(:resolve_bitbucket_build_status).with(repository_uuid: "{r-1}", commit: "abc123")

    ResolveBitbucketBuildStatusJob.perform_now(repository_uuid: "{r-1}", commit: "abc123")
  end

  test "an event without both says nothing to resolve" do
    GateService.expects(:resolve_bitbucket_build_status).never

    ResolveBitbucketBuildStatusJob.perform_now(repository_uuid: nil, commit: "abc123")
    ResolveBitbucketBuildStatusJob.perform_now(repository_uuid: "{r-1}", commit: nil)
  end
end
