# frozen_string_literal: true

require "test_helper"

# `bitbucket_pr_statuses_completed` end to end: created by the board tool,
# routed by repository UUID, cued by a build-status event, and decided by the
# probe against every status on the pull request's head — never by the event.
class BitbucketGateTest < ActiveSupport::TestCase
  HEAD = FakeBitbucket::Api::HEAD
  UUID = FakeBitbucket::Api::REPOSITORY_UUID

  setup do
    with_bitbucket_settings
    @bitbucket = stub_bitbucket!
    @integration = create(:integration, :bitbucket, :active)
    @project = @integration.project
    @repository = create(:repository, :bitbucket, integration: @integration, scope: @project, full_name: "acme/api",
                                                  external_id: UUID)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @user = @project.owner
    @task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @session.update!(step_run: create(:step_run, workflow_run: create(:workflow_run, project: @project, user: @user)))
  end

  def create_gate(params)
    InternalTools::BoardCreateGate.new(params: params.merge(task_id: @task.id), session: @session).execute
  end

  def gate(expected_commit: nil)
    @task.gates.create!(gate_type: :bitbucket_pr_statuses_completed, creator: @user,
                        metadata: { external_repository_id: UUID, pull_request_id: 7, expected_commit: expected_commit }.compact)
  end

  test "the board tool records the repository UUID, the pull request and the expected commit" do
    result = create_gate(gate_type: "bitbucket_pr_statuses_completed", repository_id: @repository.id,
                         pull_request_id: 7, expected_commit: HEAD)

    assert_equal 0, result[:exit_code], result[:stderr]
    created = Gate.last
    assert_equal UUID, created.metadata["external_repository_id"]
    assert_equal 7, created.metadata["pull_request_id"]
    assert_equal HEAD, created.expected_commit
    assert_equal "bitbucket", created.provider
    assert_equal "pull_request_id", created.reference_type
    assert created.ci?
  end

  test "the board tool needs a Bitbucket repository by id" do
    assert_match(/repository_id is required/, create_gate(gate_type: "bitbucket_pr_statuses_completed", pull_request_id: 7)[:stderr])

    other = create(:repository, scope: @project, integration: create(:integration, :github, :active, company: @project.company))
    result = create_gate(gate_type: "bitbucket_pr_statuses_completed", repository_id: other.id, pull_request_id: 7)
    assert_match(/not a Bitbucket repository/, result[:stderr])
  end

  test "a build-status event resolves the gate with the probe's verdict once every status finished" do
    waiting = gate(expected_commit: "#{HEAD}0123456789abcdef0123456789")
    @bitbucket.add_status(HEAD, state: "INPROGRESS", name: "tests")

    GateService.resolve_bitbucket_build_status(repository_uuid: UUID.delete("{}").upcase, commit: HEAD)
    assert waiting.reload.pending?

    @bitbucket.statuses[HEAD].first[:state] = "SUCCESSFUL"
    GateService.resolve_bitbucket_build_status(repository_uuid: UUID, commit: HEAD)

    assert waiting.reload.resolved?
    assert waiting.passed?
    assert_equal "successful", waiting.conclusion
  end

  test "an event about another commit leaves a gate waiting on its own" do
    waiting = gate(expected_commit: HEAD)

    GateReconciler.expects(:reconcile).never
    GateService.resolve_bitbucket_build_status(repository_uuid: UUID, commit: "0000000000000000")
    assert waiting.reload.pending?
  end

  test "an event for a same-named repository in another workspace reaches no gate here" do
    gate
    foreign = create(:integration, :bitbucket, :active)
    create(:repository, :bitbucket, integration: foreign, scope: foreign.project, full_name: "acme/api",
                                    external_id: "{00000000-0000-4000-8000-0000000000fe}")

    GateReconciler.expects(:reconcile).never
    GateService.resolve_bitbucket_build_status(repository_uuid: "{00000000-0000-4000-8000-0000000000fe}", commit: HEAD)
  end

  test "the sweep probes a Bitbucket gate by the repository's UUID, not its name" do
    waiting = gate
    @repository.update!(full_name: "acme/renamed")
    @bitbucket.add_status(HEAD, state: "FAILED")

    result = Ci::GateProbe.new(waiting).call

    assert result.completed?
    assert_equal "failed", result.conclusion
  end
end
