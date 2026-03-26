# frozen_string_literal: true

require "test_helper"

class ResolveGitlabPipelineJobTest < ActiveJob::TestCase
  test "calls WaitService.resolve_gitlab_pipeline with correct args" do
    WaitService.expects(:resolve_gitlab_pipeline).with(
      repo_full_name: "group/app",
      pipeline_id: 1234,
      status: "success",
      mr_iid: 42
    )

    ResolveGitlabPipelineJob.perform_now(
      repo_full_name: "group/app",
      pipeline_id: 1234,
      status: "success",
      mr_iid: 42
    )
  end

  test "passes nil mr_iid when not provided" do
    WaitService.expects(:resolve_gitlab_pipeline).with(
      repo_full_name: "group/app",
      pipeline_id: 9999,
      status: "failed",
      mr_iid: nil
    )

    ResolveGitlabPipelineJob.perform_now(
      repo_full_name: "group/app",
      pipeline_id: 9999,
      status: "failed"
    )
  end
end
