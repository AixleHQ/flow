# frozen_string_literal: true

require "test_helper"

class Tools::ExecutionQuotaTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
    @tool = create(:tool, scope: @company, name: "my_linter", docker_image: "l:1")
    TemporalService.stubs(:start_workflow).returns({ ok: true, workflow_id: "wf", run_id: "r" })
  end

  def dispatch
    Tools::CallExecutor.execute(@tool, {}, @session)
  end

  test "dispatches freely under the cap and rejects at capacity with a structured error" do
    Tools::ExecutionQuota.stubs(:limit).returns(2)

    assert_equal 0, dispatch[:exit_code]
    assert_equal 0, dispatch[:exit_code]

    result = dispatch
    assert_equal 1, result[:exit_code]
    assert_match(/capacity reached.*2\/2 running/m, result[:stderr])
    assert_match(/retry/i, result[:stderr])
  end

  test "a finished execution frees the slot" do
    Tools::ExecutionQuota.stubs(:limit).returns(1)
    first = dispatch
    assert_equal 1, dispatch[:exit_code]

    ToolResult.find_by(execution_id: first[:stdout])
              .complete!(exit_code: 0, stdout: "done", stderr: "", duration_ms: 5)

    assert_equal 0, dispatch[:exit_code]
  end

  test "other companies' executions do not count against the cap" do
    Tools::ExecutionQuota.stubs(:limit).returns(1)
    other_user = create(:user, :with_company)
    other_project = create(:project, company: other_user.company, owner: other_user)
    other_session = create(:terminal_session, :agent_session, user: other_user, project: other_project)
    other_tool = create(:tool, scope: other_user.company, name: "their_tool", docker_image: "t:1")

    assert_equal 0, Tools::CallExecutor.execute(other_tool, {}, other_session)[:exit_code]
    assert_equal 0, dispatch[:exit_code]
  end

  test "limit 0 disables the quota" do
    Tools::ExecutionQuota.stubs(:limit).returns(0)

    6.times { assert_equal 0, dispatch[:exit_code] }
  end
end
