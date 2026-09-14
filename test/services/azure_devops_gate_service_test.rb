# frozen_string_literal: true

require "test_helper"

# Routing and evidence rules for Azure CI gates, which differ from the other
# providers in two ways that matter.
class AzureDevopsGateServiceTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @project)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @user = @project.owner
    @task = create(:board_task, board: @board, board_column: @column, assignee: @user)
  end

  def build_gate(metadata)
    @task.gates.create!(gate_type: :azure_devops_build_completed, metadata: metadata, creator: @user)
  end

  def policy_gate(metadata)
    @task.gates.create!(gate_type: :azure_devops_pr_policies_satisfied, metadata: metadata, creator: @user)
  end

  test "resolves a build gate matching the repository GUID and build id" do
    gate = build_gate({ external_repository_id: @repository.external_id, build_id: 77 })

    TaskService.expects(:resolve_gate).with(
      gate: gate, resolution_data: { conclusion: "succeeded" }
    ).once

    GateService.resolve_azure_devops_build(
      external_repository_id: @repository.external_id, build_id: 77, result: "succeeded"
    )
  end

  # The whole reason Azure gates do not use `for_repository`: `full_name` is a
  # display value two organizations can share and a rename changes, so routing on
  # it would deliver one organization's build to another company's board.
  test "a build in another organization's repository does not resolve this gate" do
    gate = build_gate({ external_repository_id: @repository.external_id, build_id: 77 })
    foreign = create(:integration, :azure_devops, :active)
    create(:repository, :azure_devops, integration: foreign, scope: foreign.project,
                        full_name: @repository.full_name, external_id: SecureRandom.uuid)

    TaskService.expects(:resolve_gate).never

    GateService.resolve_azure_devops_build(
      external_repository_id: Repository.last.external_id, build_id: 77, result: "succeeded"
    )
    assert gate.reload.pending?
  end

  # A verdict about a different commit belongs to code nobody is waiting on.
  test "a build against a different commit leaves the gate pending" do
    build_gate({ external_repository_id: @repository.external_id, build_id: 77, expected_commit: "abc123" })

    TaskService.expects(:resolve_gate).never

    GateService.resolve_azure_devops_build(
      external_repository_id: @repository.external_id, build_id: 77, result: "succeeded", commit: "def456"
    )
  end

  test "a build against the expected commit resolves and records it" do
    gate = build_gate({ external_repository_id: @repository.external_id, build_id: 77, expected_commit: "abc123" })

    TaskService.expects(:resolve_gate).with(
      gate: gate, resolution_data: { conclusion: "succeeded", commit: "abc123" }
    ).once

    GateService.resolve_azure_devops_build(
      external_repository_id: @repository.external_id, build_id: 77, result: "succeeded", commit: "abc123"
    )
  end

  # A gate created without an expected commit keeps the other providers'
  # behaviour: any verdict counts.
  test "a gate with no expected commit accepts a verdict from any commit" do
    gate = build_gate({ external_repository_id: @repository.external_id, build_id: 77 })

    TaskService.expects(:resolve_gate).with(
      gate: gate, resolution_data: { conclusion: "failed", commit: "whatever" }
    ).once

    GateService.resolve_azure_devops_build(
      external_repository_id: @repository.external_id, build_id: 77, result: "failed", commit: "whatever"
    )
  end

  # == branch policies ==

  test "an approved policy set resolves the gate" do
    gate = policy_gate({ external_repository_id: @repository.external_id, pull_request_id: 9 })

    TaskService.expects(:resolve_gate).with(
      gate: gate, resolution_data: { conclusion: "approved" }
    ).once

    GateService.resolve_azure_devops_pr_policies(
      external_repository_id: @repository.external_id, pull_request_id: 9, satisfied: true
    )
  end

  # "Not approved yet" is the normal in-flight state, not a verdict. Resolving on
  # it would mark CI green while reviewers are still looking.
  test "an unsatisfied policy set leaves the gate pending" do
    gate = policy_gate({ external_repository_id: @repository.external_id, pull_request_id: 9 })

    TaskService.expects(:resolve_gate).never

    GateService.resolve_azure_devops_pr_policies(
      external_repository_id: @repository.external_id, pull_request_id: 9,
      satisfied: false, unsatisfied: [ "Minimum number of reviewers" ]
    )
    assert gate.reload.pending?
  end
end
