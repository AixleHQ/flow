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

    test "reports empty workflows, blank instructions and resources that are disabled or not in the project" do
      assert_includes validate["errors"], "Workflow has no steps"

      step = create(:step, workflow: @workflow, name: "Review", instructions: "")
      disabled = create(:mcp_server, scope: @project, enabled: false)
      step.update!(mcp_server_ids: [ disabled.id ])
      foreign = create(:repository, scope: create(:project, :standalone))
      StepResourceLink.replace!(step, :repository_id, [ foreign.id ])

      errors = validate["errors"]

      assert_includes errors, "Step 'Review' has no instructions"
      assert errors.any? { |e| e.include?("mcp server #{disabled.id}") }
      assert errors.any? { |e| e.include?("repository #{foreign.id}") }
      assert validate["warnings"].any? { |w| w.include?("no agent") }
    end

    test "warns when a step's Coder tool has no Coder integration attached, and not once one is" do
      coder = create(:integration, :coder, :active, company: @company, project: @project, connected_by: @user)
      tool = Tool.shadow_for(Tools::Registry.fetch("coder_ssh_exec"))
      step = create(:step, workflow: @workflow, name: "Build", instructions: "Run the build",
                           agent: create(:agent, scope: @project), tool_ids: [ tool.id ])

      assert validate["warnings"].any? { |w| w.include?("Step 'Build' uses tool coder_ssh_exec") && w.include?("coder integration") }

      step.update!(integration_ids: [ coder.id ])

      assert validate["warnings"].none? { |w| w.include?("coder_ssh_exec") }
      assert_empty validate["errors"]
    end

    test "reports an integration that is missing, inactive or not attachable" do
      inactive = create(:integration, :coder, status: :inactive, company: @company, project: @project, connected_by: @user)
      create(:step, workflow: @workflow, name: "Build", instructions: "Run", agent: create(:agent, scope: @project),
                    integration_ids: [ inactive.id ])

      assert_includes validate["errors"],
                      "Step 'Build' links integration #{inactive.id}, which is missing, disabled or not in this project"
    end

    test "reports an AWS role whose integration is no longer active" do
      integration = create(:integration, :aws_oidc, company: @company, project: @project)
      role = create(:aws_oidc_role, integration: integration)
      create(:step, workflow: @workflow, name: "Diagnose", instructions: "Read the logs", aws_oidc_role_ids: [ role.id ])

      assert_empty validate["errors"]

      integration.update!(status: :inactive)

      assert_includes validate["errors"],
                      "Step 'Diagnose' links aws oidc role #{role.id}, which is missing, disabled or not in this project"
    end

    # The trigger is saved first: a step whose auto-run goes off later is what
    # the save-time rule on the trigger cannot catch.
    test "an unattended trigger requires every step to allow non-interactive runs" do
      board = create(:board, project: @project)
      column = create(:board_column, board: board, name: "Planning", position: 1)
      ColumnWorkflowBinding.create!(board_column: column, workflow: @workflow, trigger_mode: "auto")
      create(:step, workflow: @workflow, name: "Draft", instructions: "Draft it", allow_non_interactive: false)

      errors = validate["errors"]

      assert errors.any? { |e| e.include?("Step 'Draft' must allow non-interactive runs") && e.include?("Planning") }
    end

    test "detects a dependency cycle" do
      a = create(:step, workflow: @workflow, instructions: "a", position: 1)
      b = create(:step, workflow: @workflow, instructions: "b", position: 2, depends_on_step_ids: [ a.id ])
      a.update_column(:depends_on_step_ids, [ b.id ])

      assert_includes validate["errors"], "Step dependencies form a cycle"
    end

    test "reports references and specs a run would trip on" do
      collect = create(:step, workflow: @workflow, name: "Collect", instructions: "Collect sources",
        agent: create(:agent, scope: @project), output_asset_specs: [ { "name" => "summary.md" } ])
      create(:step, workflow: @workflow, name: "Report", agent: create(:agent, scope: @project),
        instructions: "Summarise {{output:#{collect.id}:summary.md}} and fill in {{artifact_name}}.")

      report = validate

      refute report["valid"]
      assert(report["errors"].any? { |e| e.include?(%("Report" reads summary.md from "Collect", which does not run before it)) })
      assert(report["warnings"].any? { |e| e.include?("{{artifact_name}}") })
    end
  end
end
