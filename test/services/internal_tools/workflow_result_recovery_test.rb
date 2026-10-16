# frozen_string_literal: true

require "test_helper"

class InternalTools::WorkflowResultRecoveryTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @source = create(:step, workflow: @workflow, position: 1)
    @current = create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [ @source.id ])
    @run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    @source_run = create(:step_run, :completed, workflow_run: @run, step: @source)
    @current_run = create(:step_run, :running, workflow_run: @run, step: @current)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @current_run)
  end

  test "a shortened note carries a recovery call that returns the complete constraint" do
    note = ("Background. " * 100) + "MUST preserve /billing"
    @source_run.update!(step_note: note)

    content = section("previous-steps")
    assert_not_includes content, "MUST preserve /billing"
    assert_includes content, "get_step_result(step_run_id: #{@source_run.id})"
    result = read_result(step_run_id: @source_run.id)
    assert_equal note, result["note"]
  end

  test "large structured substep data is recoverable instead of cut into invalid JSON" do
    data = { "details" => "x" * 500, "preserve_endpoint" => true }
    sub_run = create(:sub_step_run, :completed, step_run: @source_run,
      sub_step: create(:sub_step, step: @source), note: "Evidence. " * 50, data: data)

    content = section("previous-steps")
    assert_not_includes content, "→ data:"
    assert_includes content, "get_step_result(step_run_id: #{@source_run.id}, sub_step_run_id: #{sub_run.id})"
    recovered = read_result(step_run_id: @source_run.id, sub_step_run_id: sub_run.id)
    assert_equal data, recovered.dig("sub_step", "data")
    assert_equal sub_run.note, recovered.dig("sub_step", "note")

    sub_run.update!(data: { "preserve_endpoint" => true })
    line = section("previous-steps").lines.find { |value| value.include?("→ data:") }
    assert_equal({ "preserve_endpoint" => true }, JSON.parse(line.split("→ data: ", 2).last))
  end

  test "current substep data uses the same full-result retrieval path" do
    sub_run = create(:sub_step_run, step_run: @current_run,
      sub_step: create(:sub_step, step: @current), data: { "details" => "x" * 500 })

    content = section("sub-steps")
    assert_not_includes content, "→ data:"
    assert_includes content, "get_step_result(step_run_id: #{@current_run.id}, sub_step_run_id: #{sub_run.id})"
    assert_equal sub_run.data, read_result(step_run_id: @current_run.id, sub_step_run_id: sub_run.id).dig("sub_step", "data")
  end

  test "secondary compression of short arrow notes still leaves full recovery references" do
    @source_run.update!(step_note: "→ #{'x' * 120} preserve billing")
    sub_run = create(:sub_step_run, :completed, step_run: @source_run,
      sub_step: create(:sub_step, step: @source), note: "Evidence\n→ #{'y' * 110} keep API")
    sections = ContextBuilders::WorkflowContext.new(@session).build
    sections << ContextSection.new(tag: "contract", priority: :critical, content: "x" * 25_000)

    rendered = ContextRenderer.render(sections)

    assert_not_includes rendered, "preserve billing"
    assert_includes rendered, "get_step_result(step_run_id: #{@source_run.id})"
    assert_includes rendered, "get_step_result(step_run_id: #{@source_run.id}, sub_step_run_id: #{sub_run.id})"
    assert_equal @source_run.step_note, read_result(step_run_id: @source_run.id)["note"]
    assert_equal sub_run.note, read_result(step_run_id: @source_run.id, sub_step_run_id: sub_run.id).dig("sub_step", "note")
  end

  test "full reads reject another workflow run and a substep from another step" do
    other_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    other = create(:step_run, :completed, workflow_run: other_run, step: @source, step_note: "Foreign note")
    foreign_sub = create(:sub_step_run, step_run: @current_run, sub_step: create(:sub_step, step: @current))

    result = InternalTools::GetStepResult.new(params: { step_run_id: other.id }, session: @session).execute
    assert_equal 1, result[:exit_code]
    assert_not_includes result[:stdout], "Foreign note"
    result = InternalTools::GetStepResult.new(
      params: { step_run_id: @source_run.id, sub_step_run_id: foreign_sub.id }, session: @session
    ).execute
    assert_equal 1, result[:exit_code]
  end

  private

  def section(tag)
    ContextBuilders::WorkflowContext.new(@session).build.find { |value| value.tag == tag }.content
  end

  def read_result(**params)
    result = InternalTools::GetStepResult.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code]
    JSON.parse(result[:stdout])
  end
end
