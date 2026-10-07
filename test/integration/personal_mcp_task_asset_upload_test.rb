# frozen_string_literal: true

require "test_helper"

# Attaching files to a board task from the personal MCP server. Binary bytes
# never travel in tool arguments: create_task_asset_upload hands out a storage
# slot, the caller PUTs to it, and attach_task_asset turns the slot into an
# asset. Short text arrives in `content` instead.
class PersonalMCPTaskAssetUploadTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00".b

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    board = create(:board, project: @project)
    column = create(:board_column, board: board, name: "To Do", position: 1)
    @task = create(:board_task, board: board, board_column: column, title: "Billing tab")
    @other_task = create(:board_task, board: board, board_column: column, title: "Something else")
    @token = @user.regenerate_mcp_token!
  end

  test "a file PUT to the upload URL becomes an asset on the task" do
    upload = payload(call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id,
                                                           filename: "01-billing-active.png"))
    assert_equal "PUT", upload["method"]
    put_bytes(upload["upload_url"], PNG)

    attached = payload(call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id,
                                                      upload_id: upload["upload_id"], tags: [ "screenshot" ]))

    asset = @task.task_assets.sole
    assert_equal attached["id"], asset.id
    assert_equal "01-billing-active.png", asset.name
    assert_equal "image/png", asset.file.mime_type
    assert_equal PNG.bytesize, asset.file.size
    assert_equal [ "screenshot" ], asset.tags
    assert_equal @user, asset.author
    assert_equal "store", asset.file.storage_key.to_s
  end

  test "short text is attached in one call" do
    attached = payload(call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id,
                                                      name: "notes.md", content: "# Findings\n\nAll green.\n"))

    asset = @task.task_assets.find(attached["id"])
    assert_equal "text/markdown", asset.file.mime_type
    assert_equal "# Findings\n\nAll green.\n", asset.file.read
  end

  test "attaching before anything was uploaded says what to do" do
    upload = payload(call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id,
                                                           filename: "late.png"))

    body = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id, upload_id: upload["upload_id"])

    assert tool_error?(body)
    assert_match(/PUT the file to its upload_url first/, text(body))
    assert_empty @task.task_assets
  end

  # The upload_id names its task and user, so it cannot be spent elsewhere.
  test "an upload_id cannot be spent on another task" do
    upload = payload(call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id,
                                                           filename: "a.png"))
    put_bytes(upload["upload_url"], PNG)

    body = call_tool("attach_task_asset", project_id: @project.id, task_id: @other_task.id,
                                          upload_id: upload["upload_id"])

    assert tool_error?(body)
    assert_match(/another task or user/, text(body))
    assert_empty @other_task.task_assets
  end

  test "an expired or altered upload_id is refused" do
    upload = payload(call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id,
                                                           filename: "a.png"))
    put_bytes(upload["upload_url"], PNG)

    altered = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id,
                                             upload_id: "#{upload['upload_id']}x")
    assert_match(/invalid or has expired/, text(altered))

    travel 2.hours do
      expired = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id,
                                               upload_id: upload["upload_id"])
      assert_match(/invalid or has expired/, text(expired))
    end
    assert_empty @task.task_assets
  end

  test "it takes an upload or text, not both and not neither" do
    both = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id,
                                          upload_id: "anything", content: "x", name: "x.txt")
    assert_match(/not both/, text(both))

    neither = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id)
    assert_match(/upload_id .* or content/, text(neither))

    unnamed = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id, content: "x")
    assert_match(/name is required/, text(unnamed))
  end

  test "text over 1 MB is sent to the upload instead" do
    body = call_tool("attach_task_asset", project_id: @project.id, task_id: @task.id, name: "big.log",
                                          content: "a" * (1.megabyte + 1))

    assert_match(/upload it with create_task_asset_upload/, text(body))
    assert_empty @task.task_assets
  end

  # The same policy as the UI's attach button: a read-only viewer cannot.
  test "a viewer cannot attach" do
    viewer = create(:user, :viewer, :onboarding_completed, company: @company,
                                                           email: "client-#{SecureRandom.hex(3)}@external.com")
    @project.add_collaborator(viewer)

    body = call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id, filename: "a.png",
                                                 token: viewer.regenerate_mcp_token!)

    assert tool_error?(body)
    assert_match(/Not allowed/, text(body))
  end

  test "another company's task is out of reach" do
    stranger = create(:user, :with_company)

    body = call_tool("create_task_asset_upload", project_id: @project.id, task_id: @task.id, filename: "a.png",
                                                 token: stranger.regenerate_mcp_token!)

    assert tool_error?(body)
    assert_empty @task.task_assets
  end

  private

  def call_tool(name, token: @token, **args)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")
  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def tool_error?(body) = body.dig("result", "isError")

  # Test storage cannot sign uploads, so the URL is the dev/test stand-in, which
  # takes the object key in its path. Writing to that key is what the PUT does.
  def put_bytes(url, bytes)
    key = URI(url).path.split("/api/v1/assets/upload/").last
    Shrine.storages[:cache].upload(StringIO.new(bytes), key.delete_prefix("cache/"))
  end
end
