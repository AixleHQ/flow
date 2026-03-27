# frozen_string_literal: true

require "test_helper"

class WorkflowSystemScopeTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
  end

  test "system workflow is valid with scope_type=System and scope_id=0" do
    wf = Workflow.new(scope_type: "System", scope_id: 0, name: "System WF")
    assert wf.valid?, "System workflow should be valid: #{wf.errors.full_messages}"
  end

  test "system workflow excluded from visible_for_project" do
    Workflow.create!(scope_type: "System", scope_id: 0, name: "Hidden WF")
    create(:workflow, scope: @project, name: "Visible WF")

    visible = Workflow.visible_for_project(@project)
    names = visible.pluck(:name)
    assert_includes names, "Visible WF"
    refute_includes names, "Hidden WF"
  end

  test "system workflow excluded from visible_for_company" do
    Workflow.create!(scope_type: "System", scope_id: 0, name: "System Only")
    create(:workflow, scope: @company, name: "Company WF")

    visible = Workflow.visible_for_company(@company)
    names = visible.pluck(:name)
    assert_includes names, "Company WF"
    refute_includes names, "System Only"
  end

  test "system workflow excluded from belonging_to_company" do
    Workflow.create!(scope_type: "System", scope_id: 0, name: "System X")

    belonging = Workflow.belonging_to_company(@company)
    refute belonging.pluck(:name).include?("System X")
  end

  test "Workflow.palad_builder returns system workflow" do
    wf = Workflow.create!(scope_type: "System", scope_id: 0, name: "Palad Builder")
    assert_equal wf.id, Workflow.palad_builder.id
  end

  test "system? returns true for system workflows" do
    wf = Workflow.create!(scope_type: "System", scope_id: 0, name: "Sys")
    assert wf.system?
  end

  test "scope_indicator returns system for system workflows" do
    wf = Workflow.create!(scope_type: "System", scope_id: 0, name: "Sys2")
    assert_equal "system", wf.scope_indicator
  end

  test "system agent is valid" do
    agent = Agent.new(
      scope_type: "System", scope_id: 0,
      name: "sys_agent", title: "System Agent", persona: "A system agent."
    )
    assert agent.valid?, "System agent should be valid: #{agent.errors.full_messages}"
  end
end
