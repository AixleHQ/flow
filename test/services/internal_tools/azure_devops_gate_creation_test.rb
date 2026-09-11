# frozen_string_literal: true

require "test_helper"

# Azure gates were creatable nowhere: Gate, GateService and Ci::GateProbe all
# knew the two types while BoardCreateGate's allowlist did not, so the whole
# gate half of the extension was unreachable. These pin the way in.
class InternalTools::AzureDevopsGateCreationTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @project)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @user = @project.owner
    @task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @step_run = create(:step_run, workflow_run: create(:workflow_run, project: @project, user: @user))
    @session.update!(step_run: @step_run)
  end

  def create_gate(params)
    InternalTools::BoardCreateGate.new(params: params.merge(task_id: @task.id), session: @session).execute
  end

  test "a build gate records the repository GUID, the build id and the expected commit" do
    result = create_gate(gate_type: "azure_devops_build_completed", repository_id: @repository.id,
                         build_id: 4242, expected_commit: "abc123")

    assert_equal 0, result[:exit_code], result[:stderr]
    gate = Gate.last
    assert_equal "azure_devops_build_completed", gate.gate_type
    assert_equal @repository.external_id, gate.metadata["external_repository_id"]
    assert_equal 4242, gate.metadata["build_id"]
    assert_equal "abc123", gate.expected_commit
    # Routing is on the GUID: a display name would send one organization's build
    # to another's board.
    refute gate.metadata.key?("repo_full_name")
  end

  test "a policy gate records the pull request id" do
    result = create_gate(gate_type: "azure_devops_pr_policies_satisfied", repository_id: @repository.id,
                         pull_request_id: 9)

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_equal 9, Gate.last.metadata["pull_request_id"]
  end

  test "the gate is reconcilable, so a lost delivery cannot park the task forever" do
    create_gate(gate_type: "azure_devops_build_completed", repository_id: @repository.id, build_id: 4242)

    gate = Gate.last
    assert gate.ci?
    assert_equal "azure_devops", gate.provider
    assert_includes Gate.reconcilable(gate.created_at + Gate.reconcile_grace + 1.minute), gate
  end

  test "an Azure gate needs a repository id rather than a name" do
    result = create_gate(gate_type: "azure_devops_build_completed", build_id: 4242)

    assert_equal 1, result[:exit_code]
    assert_match(/repository_id is required/, result[:stderr])
  end

  test "a repository from another project cannot be gated" do
    foreign = create(:integration, :azure_devops, :active)
    foreign_repository = create(:repository, :azure_devops, integration: foreign, scope: foreign.project)

    result = create_gate(gate_type: "azure_devops_build_completed", repository_id: foreign_repository.id,
                         build_id: 4242)

    assert_equal 1, result[:exit_code]
    assert_match(/not linked to this task's project/, result[:stderr])
  end

  test "a non-Azure repository is refused for an Azure gate" do
    github = create(:integration, :github, :active, company: @project.company, connected_by: @user)
    repo = create(:repository, integration: github, scope: @project)

    result = create_gate(gate_type: "azure_devops_build_completed", repository_id: repo.id, build_id: 4242)

    assert_equal 1, result[:exit_code]
    assert_match(/not an Azure DevOps repository/, result[:stderr])
  end

  test "a build id must be positive" do
    result = create_gate(gate_type: "azure_devops_build_completed", repository_id: @repository.id, build_id: 0)

    assert_equal 1, result[:exit_code]
    assert_match(/build_id must be a positive integer/, result[:stderr])
  end
end
