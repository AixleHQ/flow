# frozen_string_literal: true

require "test_helper"

class ResolveGitlabPipelineJobTest < ActiveJob::TestCase
  test "routes a delivery to the repository it authenticated as" do
    company = create(:company)
    user = create(:user, company: company)
    repository = create(:repository, full_name: "group/app", scope: create(:project, company: company, owner: user),
                                     integration: create(:integration, :gitlab, :active, company: company, connected_by: user))
    GateService.expects(:resolve_gitlab_pipeline).with(
      repository: repository, repo_full_name: "group/app", pipeline_id: 1234, status: "success", mr_iid: 42
    )

    ResolveGitlabPipelineJob.perform_now(repository_id: repository.id, pipeline_id: 1234, status: "success", mr_iid: 42)
  end

  # Queued before deliveries named their repository.
  test "a job that carries only the path still resolves by it" do
    GateService.expects(:resolve_gitlab_pipeline).with(
      repository: nil, repo_full_name: "group/app", pipeline_id: 9999, status: "failed", mr_iid: nil
    )

    ResolveGitlabPipelineJob.perform_now(repo_full_name: "group/app", pipeline_id: 9999, status: "failed")
  end
end
