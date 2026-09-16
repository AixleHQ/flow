# frozen_string_literal: true

require "test_helper"

class InternalTools::PromoteAssetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @project)
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

  test "share_url is null until the promoted asset is shared" do
    result = run_tool(name: "report.md")

    payload = JSON.parse(result[:stdout])
    assert_nil payload["share_url"]
  end

  test "share_url is present when re-promoting an already-shared asset" do
    first = JSON.parse(run_tool(name: "report.md")[:stdout])
    Asset.find(first["asset_id"]).share!

    result = run_tool(name: "report.md")

    payload = JSON.parse(result[:stdout])
    asset = Asset.find(payload["asset_id"])
    assert_includes payload["share_url"], "/share/#{asset.public_token}"
  end

  # An invalid folder used to surface to the agent as a raw RecordInvalid from deep inside the
  # export service; it is the agent's own argument, so it gets a tool error it can act on.
  test "returns a tool error naming the rule when the folder is invalid" do
    result = run_tool(name: "report.md", folder: "docs/sub")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "docs/sub"
    assert { Asset.where(scope: @project, name: "report.md").none? }
  end

  test "promotes into the trimmed folder, spaces inside it kept" do
    result = run_tool(name: "report.md", folder: "  Q3 reports  ")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "Q3 reports", payload["folder"]
    assert_equal "Q3 reports", Asset.find(payload["asset_id"]).folder
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
