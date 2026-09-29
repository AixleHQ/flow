# frozen_string_literal: true

require "test_helper"

class Versions::LaunchRecordTest < ActiveSupport::TestCase
  setup do
    @run = create(:workflow_run)
    @project = @run.project
    @workflow = @run.workflow
    @actor = Versions::Actor.ui(@run.user)
  end

  test "a step launch names the workflow version and each resource version it got" do
    agent = create(:agent, scope: @project)
    skill = create(:skill, scope: @project)
    tool = create(:tool, scope: @project)
    server = create(:mcp_server, scope: @project)
    step = create(:step, workflow: @workflow, agent: agent)
    Versions.save!(@workflow, actor: @actor) { @workflow.update!(description: "v") }
    step_run = create(:step_run, workflow_run: @run, step: step)
    session = create(:terminal_session, user: @run.user, project: @project, configured_agent: agent)
    session.skills << skill
    session.tools << tool
    session.mcp_servers << server

    Versions::LaunchRecord.record!(session, step_run: step_run)

    assert_equal @workflow.latest_version, step_run.reload.workflow_version
    ids = session.reload.version_ids
    assert_equal @workflow.latest_version.id, ids["workflow"]
    assert_equal agent.latest_version.id, ids["agent"]
    assert_equal [ skill.latest_version.id ], ids["skills"]
    assert_equal [ tool.latest_version.id ], ids["tools"]
    assert_equal [ server.latest_version.id ], ids["mcp_servers"]
    assert agent.latest_version.baseline?, "an entity never saved since history began gets its baseline at launch"
  end

  test "a save between two steps shows up as the later step naming the newer version" do
    first_step = create(:step, workflow: @workflow, name: "One")
    second_step = create(:step, workflow: @workflow, name: "Two")
    first_run = create(:step_run, workflow_run: @run, step: first_step)
    Versions::LaunchRecord.record!(create(:terminal_session, user: @run.user, project: @project), step_run: first_run)

    Versions.save!(@workflow, actor: @actor) { second_step.update!(instructions: "changed mid-run") }
    second_run = create(:step_run, workflow_run: @run, step: second_step)
    Versions::LaunchRecord.record!(create(:terminal_session, user: @run.user, project: @project), step_run: second_run)

    assert_equal [ 1, 2 ], [ first_run.reload.workflow_version.number, second_run.reload.workflow_version.number ]
  end
end
