# frozen_string_literal: true

require "test_helper"

class InternalTools::ShareAssetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @asset = create(:asset, scope: @project, created_by: @user, name: "diagram.html")

    workflow = create(:workflow, scope: @project)
    @run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @session = create(:terminal_session, session_type: "workflow_step", user: @user, project: @project)
    create(:step_run, workflow_run: @run, step: create(:step, workflow: workflow), terminal_session: @session)
  end

  def run_tool(params)
    InternalTools::ShareAsset.new(params: params, session: @session).execute
  end

  def create_task(board)
    create(:board_task, board: board, board_column: create(:board_column, board: board))
  end

  test "shares an asset by id and returns a stable link" do
    result = run_tool(asset_id: @asset.id)

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    @asset.reload
    assert @asset.public?
    assert @asset.public_token.present?
    assert payload["public"]
    assert_includes payload["share_url"], "/share/#{@asset.public_token}"
  end

  test "records the session and the person a share was made for" do
    run_tool(asset_id: @asset.id)

    @asset.reload
    assert_equal @session.id, @asset.shared_in_session_id
    assert_equal @user.id, @asset.shared_by_id
    assert_not_nil @asset.shared_at
  end

  # Every project of the company sees a company asset; one step's session does
  # not get to publish it.
  test "a company asset cannot be shared from a project's session" do
    company_asset = create(:asset, scope: @company, created_by: @user, name: "handbook.pdf")

    result = run_tool(asset_id: company_asset.id)

    assert_not_equal 0, result[:exit_code]
    assert_not company_asset.reload.shared?
  end

  test "resolves an asset by name" do
    result = run_tool(name: "diagram.html")

    assert_equal 0, result[:exit_code]
    assert @asset.reload.public?
  end

  test "returns the same link on repeat calls (token is stable)" do
    first = JSON.parse(run_tool(asset_id: @asset.id)[:stdout])
    token = @asset.reload.public_token
    second = JSON.parse(run_tool(asset_id: @asset.id)[:stdout])

    assert_equal token, @asset.reload.public_token
    assert_equal first["share_url"], second["share_url"]
  end

  test "returns error when neither asset_id nor name is given" do
    result = run_tool({})

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "asset_id or name"
  end

  test "returns error when the asset is not in the project" do
    other = create(:asset, :with_company_scope, created_by: @user)

    result = run_tool(asset_id: other.id)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  test "shares an output of this run" do
    output = create(:workflow_run_asset, workflow_run: @run, name: "report.md")

    payload = JSON.parse(run_tool(source: "run", name: "report.md")[:stdout])

    assert_equal "run", payload["source"]
    assert_includes payload["share_url"], "/share/#{output.reload.public_token}"
    assert_equal @session.id, output.shared_in_session_id
  end

  test "an output of another run cannot be shared" do
    other_run = create(:workflow_run, workflow: @run.workflow, project: @project, user: @user)
    output = create(:workflow_run_asset, workflow_run: other_run)

    result = run_tool(source: "run", asset_id: output.id)

    assert_equal 1, result[:exit_code]
    assert_not output.reload.shared?
  end

  test "shares a file attached to a task on this project's board" do
    task = create_task(create(:board, project: @project))
    attachment = create(:task_asset, board_task: task, name: "mockup.png")

    payload = JSON.parse(run_tool(source: "task", task_id: task.id, name: "mockup.png")[:stdout])

    assert_equal "task", payload["source"]
    assert_equal @session.id, attachment.reload.shared_in_session_id
  end

  test "a task on another project's board is out of reach" do
    create(:board, project: @project)
    task = create_task(create(:board, project: create(:project, company: @company, owner: @user)))
    attachment = create(:task_asset, board_task: task)

    result = run_tool(source: "task", task_id: task.id, asset_id: attachment.id)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Task not found"
    assert_not attachment.reload.shared?
  end

  test "a task attachment needs its task" do
    result = run_tool(source: "task", name: "mockup.png")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "task_id"
  end

  test "refuses an unknown source" do
    result = run_tool(source: "company", asset_id: @asset.id)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "source"
    assert_not @asset.reload.shared?
  end

  test "raises outside workflow context" do
    no_wf = Object.new
    no_wf.define_singleton_method(:step_run) { nil }

    handler = InternalTools::ShareAsset.new(params: { asset_id: @asset.id }, session: no_wf)
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
