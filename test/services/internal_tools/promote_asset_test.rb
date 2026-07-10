# frozen_string_literal: true

require "test_helper"

class InternalTools::PromoteAssetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    @run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: @run, step: step)
    @wra = create(:workflow_run_asset, workflow_run: @run, name: "report.md",
                  file: WorkflowRunAssetUploader.upload(StringIO.new("hello"), :store))

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  def run_tool(params)
    InternalTools::PromoteAsset.new(params: params, session: @session).execute
  end

  test "promotes a workflow output asset to a versioned project asset" do
    result = run_tool(name: "report.md")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    asset = Asset.find(payload["asset_id"])
    assert_equal "Project", asset.scope_type
    assert_equal @project.id, asset.scope_id
    assert_equal "report.md", asset.name
    assert_equal "project", payload["scope"]
    assert_equal 1, payload["version"]
    assert_equal 1, asset.versions.count
  end

  test "appends a new version when the project asset already exists" do
    run_tool(name: "report.md")
    result = run_tool(name: "report.md")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    asset = Asset.find(payload["asset_id"])
    assert_equal 2, payload["version"]
    assert_equal 2, asset.versions.count
    assert_equal 1, Asset.where(scope: @project, name: "report.md").count
  end

  test "returns error when no matching workflow output asset exists" do
    result = run_tool(name: "missing.md")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "missing.md"
  end

  test "raises outside workflow context" do
    no_wf = Object.new
    no_wf.define_singleton_method(:step_run) { nil }

    handler = InternalTools::PromoteAsset.new(params: { name: "report.md" }, session: no_wf)
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
