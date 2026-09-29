# frozen_string_literal: true

require "test_helper"

class Web::PublicAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @asset = create(:asset, scope: @project, created_by: @user, name: "page.html")
    create(:asset_version, asset: @asset, uploaded_by: @user, content_type: "text/html",
           file: AssetFileUploader.upload(StringIO.new("<b>hi</b>"), :store))
    @token = @asset.share!
  end

  test "show renders the sandboxed viewer for a shared asset" do
    get public_asset_path(token: @token)

    assert_response :success
    assert_includes response.body, "iframe"
    assert_includes response.body, public_asset_raw_path(token: @token)
    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors"
    assert_nil response.headers["X-Frame-Options"]
  end

  test "raw streams the file with sandbox headers" do
    get public_asset_raw_path(token: @token)

    assert_response :success
    assert_equal "<b>hi</b>", response.body
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Content-Type"], "text/html"
  end

  test "show 404s for an unknown token" do
    get public_asset_path(token: "nope")
    assert_response :not_found
  end

  test "raw 404s for an unknown token" do
    get public_asset_raw_path(token: "nope")
    assert_response :not_found
  end

  test "404s once the asset is deleted" do
    @asset.soft_delete!

    get public_asset_raw_path(token: @token)
    assert_response :not_found
  end

  test "404s once the asset is unshared" do
    @asset.unshare!

    get public_asset_path(token: @token)
    assert_response :not_found
  end

  test "serves a shared run output the same sandboxed way" do
    run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @user)
    output = create(:workflow_run_asset, workflow_run: run, name: "summary.md", content_type: "text/markdown",
                                         file: WorkflowRunAssetUploader.upload(StringIO.new("# summary"), :store))
    token = output.share!

    get public_asset_path(token: token)
    assert_response :success
    assert_includes response.body, "summary.md"

    get public_asset_raw_path(token: token)
    assert_response :success
    assert_equal "# summary", response.body
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_includes response.headers["Content-Type"], "text/markdown"
  end

  test "serves a shared task attachment until it is unshared" do
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    attachment = create(:task_asset, board_task: task, author: @user, name: "notes.txt",
                                     file: TaskAssetUploader.upload(StringIO.new("task notes"), :store))
    token = attachment.share!

    get public_asset_raw_path(token: token)
    assert_response :success
    assert_equal "task notes", response.body
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    attachment.unshare!

    get public_asset_raw_path(token: token)
    assert_response :not_found
  end
end
