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

    @session = create(:terminal_session, :running, user: @user, project: @project, step_run: @step_run)
    @runtime = stub_container_runtime
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

  test "the promoter is the session's user, not the run's" do
    session_user = create(:user, company: @company)
    @session.update!(user: session_user)

    result = run_tool(name: "report.md")

    assert_equal 0, result[:exit_code]
    asset = Asset.find(JSON.parse(result[:stdout])["asset_id"])
    assert_equal session_user, asset.created_by
    assert_equal session_user, asset.versions.last.uploaded_by
  end

  test "answers with an error when the session has no user" do
    @session.stubs(:user).returns(nil)

    result = run_tool(name: "report.md")

    assert_equal 1, result[:exit_code]
    assert_match(/promoting user/, result[:stderr])
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
    result = run_tool(name: "report.md", folder: "a/..")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "a/.."
    assert { Asset.where(scope: @project, name: "report.md").none? }
  end

  test "promotes into the trimmed nested folder" do
    result = run_tool(name: "report.md", folder: "  docs/sub  ")

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal "docs/sub", payload["folder"]
    assert_equal "docs/sub", Asset.find(payload["asset_id"]).folder
  end

  test "returns error when no matching workflow output asset exists" do
    result = run_tool(name: "missing.md")

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "missing.md"
  end

  # The step's own outputs are collected into run assets only when its session
  # ends, so promoting one mid-session reads it from the container.
  test "promotes a file this session wrote to its outputs before the session ends" do
    @runtime.write_file(@session.container_id, "/workspace/outputs/reports/audit.md", "# Audit")

    result = run_tool(name: "reports/audit.md", folder: "optimize-reports")

    assert_equal 0, result[:exit_code], result[:stderr]
    asset = Asset.find(JSON.parse(result[:stdout])["asset_id"])
    assert_equal "reports/audit.md", asset.name
    assert_equal "optimize-reports", asset.folder
    assert_equal "# Audit", asset.latest_version.file.read
  end

  test "the session's own output wins over an earlier step's output of the same name" do
    @runtime.write_file(@session.container_id, "/workspace/outputs/report.md", "rewritten")

    result = run_tool(name: "report.md")

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_equal "rewritten", Asset.find(JSON.parse(result[:stdout])["asset_id"]).latest_version.file.read
  end

  test "an earlier step's output is promoted when this session wrote none" do
    result = run_tool(name: "report.md")

    assert_equal 0, result[:exit_code], result[:stderr]
    assert_equal "hello", Asset.find(JSON.parse(result[:stdout])["asset_id"]).latest_version.file.read
  end

  test "a name that leaves the outputs directory is not read from the container" do
    @runtime.write_file(@session.container_id, "/workspace/secret.txt", "secret")

    result = run_tool(name: "../secret.txt")

    assert_equal 1, result[:exit_code]
    assert { Asset.where(scope: @project).none? }
  end

  test "an empty output is refused" do
    @runtime.write_file(@session.container_id, "/workspace/outputs/empty.md", "")

    result = run_tool(name: "empty.md")

    assert_equal 1, result[:exit_code]
    assert_match(/empty/, result[:stderr])
    assert { Asset.where(scope: @project).none? }
  end

  test "an output the runtime could not read whole is refused with the reason" do
    @runtime.stubs(:read_file_result).with(@session.container_id, "/workspace/outputs/big.xlsx").returns(
      ContainerRuntime::FileRead.new(content: nil, whole: false, reason: "needs S3-compatible storage")
    )

    result = run_tool(name: "big.xlsx")

    assert_equal 1, result[:exit_code]
    assert_match(/needs S3-compatible storage/, result[:stderr])
    assert { Asset.where(scope: @project).none? }
  end

  test "raises outside workflow context" do
    no_wf = Object.new
    no_wf.define_singleton_method(:step_run) { nil }

    handler = InternalTools::PromoteAsset.new(params: { name: "report.md" }, session: no_wf)
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
