# frozen_string_literal: true

require "test_helper"

module Ci
  # The probe's own job is the lookups — repository, integration, provider, adapter
  # call — so the adapters are the seam here (stubbed with the canonical fakes,
  # testing doctrine R3) while everything else is real.
  class GateProbeTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
      @project = create(:project, company: @company, owner: @user)
      @board = create(:board, project: @project)
      @column = create(:board_column, board: @board)
      @task = create(:board_task, board: @board, board_column: @column)
      @repository = create(:repository, full_name: "org/app", scope: @project, integration: @integration)
    end

    test "asks the checks adapter about the pull request a github_checks gate names" do
      fake = FakeGithub::CheckStatusService.new(pr_result: Ci::ProbeResult.completed("success", "all green"))
      Github::CheckStatusService.stubs(:new).returns(fake)

      result = Ci::GateProbe.new(checks_gate).call

      assert result.completed?
      assert_equal "success", result.conclusion
      assert_equal({ method: :pull_request_checks, repo_full_name: "org/app", pr_number: 42 }, fake.last_call)
    end

    test "asks the checks adapter about the workflow run a github_workflow gate names" do
      fake = FakeGithub::CheckStatusService.new(run_result: Ci::ProbeResult.in_progress("still running"))
      Github::CheckStatusService.stubs(:new).returns(fake)

      result = Ci::GateProbe.new(workflow_gate).call

      assert result.in_progress?
      assert_equal({ method: :workflow_run_status, repo_full_name: "org/app", run_id: 99 }, fake.last_call)
    end

    test "asks the pipeline adapter about the pipeline a gitlab gate names" do
      gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
      create(:repository, full_name: "group/app", scope: @project, integration: gitlab_integration,
                          clone_url: "https://gitlab.com/group/app.git")
      fake = Fakes::FakeGitlabService.new(pipeline_result: Ci::ProbeResult.completed("failed", "pipeline failed"))
      Gitlab::PipelineStatusService.stubs(:new).returns(fake)

      result = Ci::GateProbe.new(pipeline_gate).call

      assert result.completed?
      assert_equal "failed", result.conclusion
      assert_equal [ "group/app", 555 ], fake.calls_for(:pipeline_status).last.args
    end

    # == unresolvable: nothing a webhook could ever fix ==

    test "a gate naming a repository the project does not have is unresolvable" do
      gate = checks_gate(metadata: { "repo_full_name" => "other/repo", "pr_number" => 42 })

      result = Ci::GateProbe.new(gate).call

      assert result.unresolvable?
      assert_match(/other\/repo is not linked to project/, result.detail)
    end

    test "a gate on a repository attached without an integration is unresolvable" do
      @repository.destroy!
      create(:repository, :public_source, full_name: "org/app", scope: @project,
                                          clone_url: "https://github.com/org/app.git")

      result = Ci::GateProbe.new(checks_gate).call

      assert result.unresolvable?
      assert_match(/attached without an integration/, result.detail)
    end

    test "a github gate on a gitlab repository is unresolvable rather than probed" do
      @repository.destroy!
      gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
      create(:repository, full_name: "org/app", scope: @project, integration: gitlab_integration,
                          clone_url: "https://gitlab.com/org/app.git")

      result = Ci::GateProbe.new(checks_gate).call

      assert result.unresolvable?
      assert_match(/gitlab repository but the gate expects github/, result.detail)
    end

    test "a gate whose metadata is missing its run identifier is unresolvable" do
      gate = checks_gate(metadata: { "repo_full_name" => "org/app" })

      result = Ci::GateProbe.new(gate).call

      assert result.unresolvable?
      assert_match(/no pr_number/, result.detail)
    end

    test "a gate whose metadata is missing the repository is unresolvable" do
      gate = checks_gate(metadata: { "pr_number" => 42 })

      result = Ci::GateProbe.new(gate).call

      assert result.unresolvable?
      assert_match(/no repo_full_name/, result.detail)
    end

    # == unavailable: try again later ==

    test "a disconnected integration is unavailable rather than unresolvable" do
      @integration.update!(status: :error)

      result = Ci::GateProbe.new(checks_gate).call

      assert result.unavailable?
      assert_match(/is error/, result.detail)
    end

    test "an adapter that blows up is reported as unavailable, not as a verdict" do
      Rails.logger.stubs(:warn)
      Github::CheckStatusService.stubs(:new).raises(RuntimeError, "boom")

      result = Ci::GateProbe.new(checks_gate).call

      assert result.unavailable?
      assert_match(/boom/, result.detail)
    end

    private

    def checks_gate(metadata: { "repo_full_name" => "org/app", "pr_number" => 42 })
      @task.gates.create!(gate_type: :github_checks_completed, metadata: metadata, creator: @user)
    end

    def workflow_gate
      @task.gates.create!(
        gate_type: :github_workflow_completed,
        metadata: { "repo_full_name" => "org/app", "run_id" => 99 },
        creator: @user
      )
    end

    def pipeline_gate
      @task.gates.create!(
        gate_type: :gitlab_pipeline_completed,
        metadata: { "repo_full_name" => "group/app", "pipeline_id" => 555 },
        creator: @user
      )
    end
  end
end
