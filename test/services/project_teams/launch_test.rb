# frozen_string_literal: true

require "test_helper"

# A team as Runs as of a trigger and as the assignee of a card: each launch goes
# to the member the team picks, and a launch nobody can take is a failed run that
# says why (docs/design/project-teams.md).
module ProjectTeams
  class LaunchTest < ActiveSupport::TestCase
    setup do
      @owner = create(:user, :with_company)
      @company = @owner.companies.first
      @project = create(:project, company: @company, owner: @owner)
      @workflow = create(:workflow, scope: @project)
      create(:step, :non_interactive, workflow: @workflow, name: "Plan")
      @anna = member("Anna")
      @pavel = member("Pavel")
      @team = ProjectTeams::Management.new(project: @project, actor: @owner)
                                      .create!(name: "Planner", member_ids: [ @anna.id, @pavel.id ])
    end

    def member(name)
      user = create(:user, company: @company, name: name)
      @project.add_collaborator(user)
      create(:agent_credential, user: user, company: @company, agent_type: "kiro_cli")
      user
    end

    def trigger
      create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner,
                               event_type: "webhook.deploy", run_as_team: @team)
    end

    def publish
      TriggerEngine.publish(event_type: "webhook.deploy", source: "webhook", project: @project,
                            data: {}, dedup_key: SecureRandom.uuid).trigger_dispatches.sole.workflow_run
    end

    test "a trigger that runs as a team starts its run as the member the team picks" do
      trigger
      TemporalWorkflowRegistry.expects(:start_workflow_execution).once.returns(ok: true)

      run = publish

      assert_equal @anna, run.user
      assert_equal @team, run.team
      assert run.pending?
    end

    test "when no member can take the run, the run fails at once and every step says why" do
      trigger
      AgentCredential.where(user: [ @anna, @pavel ]).update_all(quota_exhausted_until: 1.day.from_now)
      TemporalWorkflowRegistry.expects(:start_workflow_execution).never

      run = publish

      assert run.reload.failed?
      assert_equal WorkflowService::TEAM_UNAVAILABLE, run.failure_reason
      assert_equal @owner, run.user
      assert_equal @team, run.team
      message = run.step_runs.sole.error_message
      assert_match(/No member of team "Planner" can take this run/, message)
      assert_match(/Anna: Kiro CLI quota exhausted until/, message)
      assert_equal "dispatched", run.relay_state
      assert_nil WorkflowRunResource.new(run).to_h["teamName"], "nobody was picked, so the run names no team"
    end

    test "a card assigned to a team runs as the picked member, not the person who pressed Run" do
      board = create(:board, project: @project)
      column = create(:board_column, board: board)
      binding = ColumnWorkflowBinding.create!(board_column: column, workflow: @workflow, trigger_mode: :manual,
                                              cooldown_seconds: 0)
      task = create(:board_task, board: board, board_column: column, assignee_team: @team)
      AgentCredential.find_by!(user: @anna).update_column(:quota_exhausted_until, 1.hour.from_now)
      create(:agent_credential, user: @owner, company: @company)
      mock_workflow_execution_start

      run = TaskService.trigger_workflow(task: task, binding: binding, actor: @owner)

      assert_equal @pavel, run.user
      assert_equal @team, run.team
      assert_equal @team.id, TriggerEvent.find_by!(board_task: task).data["team_id"]
    end

    test "a failed team run started again picks from the team again" do
      trigger
      TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns(ok: true)
      run = publish
      run.update_columns(state: "failed")
      AgentCredential.find_by!(user: @anna).update_column(:quota_exhausted_until, 1.hour.from_now)
      TemporalService.stubs(:workflow_open?).returns(false)

      result = WorkflowService.retry_step(step_run: run.step_runs.sole)

      assert_equal @pavel, result[:run].user
      assert_equal @team, result[:run].team
    end
  end
end
