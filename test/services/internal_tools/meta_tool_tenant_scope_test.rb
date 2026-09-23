# frozen_string_literal: true

require "test_helper"

# A builder session edits its own project and nothing else, whatever ids the
# agent passes in.
class InternalTools::MetaToolTenantScopeTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, user: @user, project: @project, session_type: "agent_session",
                                         metadata: { aixle_builder: true })

    @foreign_company = create(:company)
    @foreign_user = create(:user, company: @foreign_company)
    @foreign_project = create(:project, company: @foreign_company, owner: @foreign_user)
    @foreign_workflow = create(:workflow, scope: @foreign_project, name: "Foreign")
    @foreign_step = create(:step, workflow: @foreign_workflow, name: "Foreign step", instructions: "secret")
  end

  test "a foreign workflow cannot be read, edited or deleted" do
    assert_not_found { call(InternalTools::MetaGetWorkflow, workflow_id: @foreign_workflow.id) }
    assert_not_found { call(InternalTools::MetaDeleteWorkflow, workflow_id: @foreign_workflow.id) }
    assert_not_found { call(InternalTools::MetaCreateStep, workflow_id: @foreign_workflow.id, name: "x", instructions: "y") }

    assert_nil @foreign_workflow.reload.deleted_at
    assert_equal 1, @foreign_workflow.steps.count
  end

  test "a foreign step and its sub-steps cannot be touched" do
    sub_step = create(:sub_step, step: @foreign_step, name: "Foreign sub")

    assert_not_found { call(InternalTools::MetaUpdateStep, step_id: @foreign_step.id, instructions: "pwned") }
    assert_not_found { call(InternalTools::MetaDeleteStep, step_id: @foreign_step.id) }
    assert_not_found { call(InternalTools::MetaCreateSubStep, step_id: @foreign_step.id, name: "x") }
    assert_not_found { call(InternalTools::MetaUpdateSubStep, sub_step_id: sub_step.id, name: "pwned") }
    assert_not_found { call(InternalTools::MetaDeleteSubStep, sub_step_id: sub_step.id) }

    assert_equal "secret", @foreign_step.reload.instructions
    assert_equal "Foreign sub", sub_step.reload.name
  end

  test "a sibling project's workflow in the same company is out of reach too" do
    sibling = create(:project, company: @company, owner: @user)
    sibling_workflow = create(:workflow, scope: sibling)

    assert_not_found { call(InternalTools::MetaDeleteWorkflow, workflow_id: sibling_workflow.id) }
    assert_nil sibling_workflow.reload.deleted_at
  end

  test "foreign board columns and column bindings cannot be touched" do
    foreign_board = create(:board, project: @foreign_project)
    foreign_column = create(:board_column, board: foreign_board, name: "Foreign col", position: 1)
    binding = ColumnWorkflowBinding.create!(board_column: foreign_column, workflow: @foreign_workflow)
    own_board = create(:board, project: @project)
    own_column = create(:board_column, board: own_board, name: "Mine", position: 1)

    assert_not_found { call(InternalTools::MetaUpdateBoardColumn, column_id: foreign_column.id, name: "pwned") }
    assert_not_found { call(InternalTools::MetaDeleteBoardColumn, column_id: foreign_column.id) }
    assert_not_found { call(InternalTools::MetaUpdateColumnBinding, binding_id: binding.id, trigger_mode: "auto") }
    assert_not_found { call(InternalTools::MetaDeleteColumnBinding, binding_id: binding.id) }
    assert_not_found { call(InternalTools::MetaCreateColumnBinding, column_id: own_column.id, workflow_id: @foreign_workflow.id) }

    assert_equal "Foreign col", foreign_column.reload.name
    assert_equal "manual", binding.reload.trigger_mode
  end

  test "a project_id or scope_id naming another project is refused" do
    assert_refused { call(InternalTools::MetaCreateWorkflow, name: "Planted", project_id: @foreign_project.id) }
    assert_refused { call(InternalTools::MetaCreateAgent, name: "planted", title: "P", persona: "p", scope_id: @foreign_project.id) }
    assert_refused { call(InternalTools::MetaListWorkflows, project_id: @foreign_project.id) }

    assert_not Workflow.exists?(name: "Planted")
    assert_not Agent.exists?(name: "planted")
  end

  test "a foreign resource cannot be wired into an own step" do
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, instructions: "do")
    foreign_mcp = create(:mcp_server, scope: @foreign_project)

    result = call(InternalTools::MetaLinkResourceToStep, step_id: step.id, resource_type: "mcp_server", resource_id: foreign_mcp.id)

    assert_equal 1, result[:exit_code]
    assert_match(/outside this project/, result[:stderr])
    assert_empty step.reload.mcp_server_ids
  end

  test "a session whose owner is only a viewer cannot edit" do
    viewer = create(:user, company: @company, membership_role: "viewer")
    @project.project_collaborators.create!(user: viewer)
    @session = create(:terminal_session, user: viewer, project: @project, session_type: "agent_session")

    error = assert_raises(InternalTools::WorkflowContextError) do
      call(InternalTools::MetaCreateWorkflow, name: "By viewer")
    end
    assert_match(/can no longer edit/, error.message)
  end

  private

  def call(tool_class, **params)
    tool_class.new(params: params, session: @session).execute
  end

  def assert_not_found
    result = yield
    assert_equal 1, result[:exit_code], "expected a not-found error, got #{result.inspect}"
    assert_match(/not found|Couldn't find/i, result[:stderr])
  rescue ActiveRecord::RecordNotFound
    pass
  end

  def assert_refused(&)
    error = assert_raises(InternalTools::WorkflowContextError, &)
    assert_match(/act only on this session's project/, error.message)
  end
end
