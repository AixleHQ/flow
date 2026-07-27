# frozen_string_literal: true

require "test_helper"

class InternalTools::ListSubStepsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: workflow)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: workflow_run, step: @step)

    @sub_step_a = create(:sub_step, step: @step, name: "Analyze", position: 1, instructions: "Analyze code")
    @sub_step_b = create(:sub_step, step: @step, name: "Report", position: 2, instructions: "Write report")

    @ssr_a = create(:sub_step_run, step_run: @step_run, sub_step: @sub_step_a, state: :completed,
      note: "Found 3 issues", data: { "issues" => 3 })
    @ssr_b = create(:sub_step_run, step_run: @step_run, sub_step: @sub_step_b, state: :pending)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  test "returns sub-step runs ordered by position" do
    result = InternalTools::ListSubSteps.new(params: {}, session: @session).execute
    assert_equal 0, result[:exit_code]

    items = JSON.parse(result[:stdout])
    assert_equal 2, items.length
    assert_equal "Analyze", items[0]["name"]
    assert_equal "Report", items[1]["name"]
  end

  test "includes all required fields" do
    result = InternalTools::ListSubSteps.new(params: {}, session: @session).execute
    items = JSON.parse(result[:stdout])
    first = items[0]

    assert_equal @ssr_a.id, first["id"]
    assert_equal 1, first["position"]
    assert_equal "Analyze", first["name"]
    assert_equal "Analyze code", first["instructions"]
    assert_equal "completed", first["status"]
    assert_equal "Found 3 issues", first["note"]
    assert_equal({ "issues" => 3 }, first["data"])
  end

  test "raises error outside workflow context" do
    no_wf_session = Object.new
    no_wf_session.define_singleton_method(:step_run) { nil }

    handler = InternalTools::ListSubSteps.new(params: {}, session: no_wf_session)
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
