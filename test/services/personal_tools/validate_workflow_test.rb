# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class ValidateWorkflowTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @workflow = create(:workflow, scope: @project)
    end

    def validate
      result = ValidateWorkflow.new(params: { project_id: @project.id, workflow_id: @workflow.id }, user: @user).execute
      JSON.parse(result[:stdout])
    end

    test "a workflow with one complete step is valid" do
      create(:step, workflow: @workflow, instructions: "Summarize the brief", agent: create(:agent, scope: @project))

      report = validate

      assert report["valid"]
      assert_empty report["errors"]
    end

    test "reports empty workflows, blank instructions and resources that are gone or disabled" do
      assert_includes validate["errors"], "Workflow has no steps"

      step = create(:step, workflow: @workflow, name: "Review", instructions: "")
      disabled = create(:mcp_server, scope: @project, enabled: false)
      step.update!(mcp_server_ids: [ disabled.id ])
      step.update_column(:repository_ids, [ 999_999 ])

      errors = validate["errors"]

      assert_includes errors, "Step 'Review' has no instructions"
      assert errors.any? { |e| e.include?("mcp server #{disabled.id}") }
      assert errors.any? { |e| e.include?("repository 999999") }
      assert validate["warnings"].any? { |w| w.include?("no agent") }
    end

    test "an unattended trigger requires every step to allow non-interactive runs" do
      create(:step, workflow: @workflow, name: "Draft", instructions: "Draft it", allow_non_interactive: false)
      board = create(:board, project: @project)
      column = create(:board_column, board: board, name: "Planning", position: 1)
      ColumnWorkflowBinding.create!(board_column: column, workflow: @workflow, trigger_mode: "auto")

      errors = validate["errors"]

      assert errors.any? { |e| e.include?("Step 'Draft' must allow non-interactive runs") && e.include?("Planning") }
    end

    test "detects a dependency cycle" do
      a = create(:step, workflow: @workflow, instructions: "a", position: 1)
      b = create(:step, workflow: @workflow, instructions: "b", position: 2, depends_on_step_ids: [ a.id ])
      a.update_column(:depends_on_step_ids, [ b.id ])

      assert_includes validate["errors"], "Step dependencies form a cycle"
    end
  end
end
