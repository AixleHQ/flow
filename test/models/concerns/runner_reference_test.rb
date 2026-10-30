# frozen_string_literal: true

require "test_helper"

# workflows.runner_id, workflow_runs.runner_id and terminal_sessions.runner_id
# (DESIGN.md §2.4): nullable references, checked against the record's project.
class RunnerReferenceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @company_runner = create(:runner, company: @company, created_by: @user)
    @project_runner = create(:runner, company: @company, created_by: @user, project: @project)
  end

  test "every existing row reads as hosted" do
    assert_nil create(:workflow, scope: @project).runner_id
    assert_nil create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project).runner_id
    assert_nil create(:terminal_session, :agent_session, user: @user, project: @project).runner_id
  end

  test "a workflow, a run and a session may name the company's runners and their project's" do
    workflow = create(:workflow, scope: @project, runner: @company_runner)
    run = create(:workflow_run, workflow: workflow, project: @project, runner: @project_runner)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, runner: @project_runner)

    assert_equal [ @company_runner, @project_runner, @project_runner ], [ workflow, run, session ].map { |r| r.reload.runner }
  end

  test "a runner of another project or company is refused" do
    other_project = create(:project, company: @company, owner: @user)
    elsewhere = create(:runner, company: @company, created_by: @user, project: other_project)
    foreign = create(:runner)

    [ elsewhere, foreign ].each do |runner|
      workflow = build(:workflow, scope: @project, runner: runner)
      assert_not workflow.valid?
      assert_includes workflow.errors[:runner], "runner_id must belong to this project (not found: #{runner.id})"

      session = build(:terminal_session, :agent_session, user: @user, project: @project, runner: runner)
      assert_not session.valid?
      assert_includes session.errors[:runner], "runner_id must belong to this project (not found: #{runner.id})"
    end
  end

  test "a reference to a runner deleted since stays valid" do
    workflow = create(:workflow, scope: @project, runner: @company_runner)
    @company_runner.soft_delete!

    assert workflow.reload.update(name: "Renamed"), workflow.errors.full_messages.to_sentence
    assert_equal @company_runner.id, workflow.runner_id

    # A restore names it again, which the tenant rule lets through: the row is there.
    restored = create(:workflow, scope: @project)
    assert restored.update(runner: @company_runner), restored.errors.full_messages.to_sentence
  end

  test "a system workflow can only run hosted" do
    workflow = build(:workflow, :system, runner: @company_runner)

    assert_not workflow.valid?
    assert_includes workflow.errors[:runner], "runner_id must belong to this project (not found: #{@company_runner.id})"
  end

  test "the database ties a workflow's and a session's runner to their company" do
    foreign = create(:runner)
    workflow = create(:workflow, scope: @project)

    assert_raises(ActiveRecord::InvalidForeignKey) { workflow.update_column(:runner_id, foreign.id) }
  end

  test "a runner removed with its project takes its references with it" do
    workflow = create(:workflow, scope: create(:project, company: @company, owner: @user))
    runner = create(:runner, company: @company, created_by: @user, project: workflow.scope)
    workflow.update!(runner: runner)

    assert_nothing_raised { workflow.scope.destroy! }
    assert_not Runner.exists?(runner.id)
  end
end
