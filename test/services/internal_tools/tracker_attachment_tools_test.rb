# frozen_string_literal: true

require "test_helper"

# The tracker file tools over a YouTrack connection, through the real provider,
# importer and exporter (docs/design/tracker-attachments.md §7).
class InternalTools::TrackerAttachmentToolsTest < ActiveSupport::TestCase
  ISSUE_1 = FakeYoutrack::Api::ISSUE_1

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    @runtime = stub_container_runtime
    @integration = create(:integration, :youtrack, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @tracker = ProjectTracker.find_by!(project: @project, external_scope_id: FakeYoutrack::Api::APP)
    @user = create(:user, company: @project.company)
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
  end

  def run_tool(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code], result[:stderr] || result[:stdout]
    JSON.parse(result[:stdout])
  end

  def tool_error(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 1, result[:exit_code], result[:stdout]
    result[:stderr].presence || result[:stdout]
  end

  def linked_task
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    ExternalResource.create!(board_task: task, kind: ExternalResource::TRACKER_ISSUE, provider: "youtrack",
                             instance: FakeYoutrack::Api::BASE_URL, external_id: ISSUE_1, data: { "key" => "APP-1" })
    task
  end

  test "listing shows restricted files and which ones this project already holds" do
    shot = @youtrack.add_file(ISSUE_1, name: "shot.png", bytes: "png", content_type: "image/png")
    @youtrack.add_file(ISSUE_1, name: "secret.txt", bytes: "s", restricted: true)

    files = run_tool(InternalTools::TrackerListAttachments, issue: "APP-1")["attachments"]

    assert_equal [ [ "shot.png", false, nil ], [ "secret.txt", true, nil ] ],
                 files.map { |f| f.values_at("name", "restricted", "task_asset_id") }
    assert_equal shot, files.first["id"]
    assert files.none? { |f| f.to_json.include?("sign=") }, "a signed URL is a credential and never reaches the agent"
  end

  test "downloading copies the files onto the linked task and into the workspace, once" do
    task = linked_task
    @youtrack.add_file(ISSUE_1, name: "log.txt", bytes: "boom", content_type: "text/plain")
    @youtrack.add_file(ISSUE_1, name: "secret.txt", bytes: "s", restricted: true)

    first = run_tool(InternalTools::TrackerDownloadAttachments, issue: "APP-1")
    second = run_tool(InternalTools::TrackerDownloadAttachments, issue: "APP-1")

    copy = task.task_assets.sole
    assert_equal [ "log.txt", "tracker", "system", Digest::SHA256.hexdigest("boom") ],
                 [ copy.name, copy.source, copy.author_type, copy.content_sha256 ]
    assert_equal "boom", copy.file.read
    assert_equal [ %w[copied skipped], %w[reused skipped] ],
                 [ first["files"].pluck("status"), second["files"].pluck("status") ]
    assert_equal "restricted", first["files"].last["reason"]
    assert_equal "/workspace/tracker/APP-1/log.txt", first["files"].first["path"]
    assert_equal 1, @youtrack.calls_to(:download).size
    assert(@runtime.execs.any? { |cmd| cmd.join(" ").include?("/workspace/tracker/APP-1/log.txt") })
    assert_equal [ "imported", "APP-1" ], [ copy.tracker_attachment.direction, copy.tracker_attachment.issue_key ]
  end

  test "without a linked task the files are only placed in the workspace" do
    @youtrack.add_file(ISSUE_1, name: "notes.md", bytes: "# hi")

    result = run_tool(InternalTools::TrackerDownloadAttachments, issue: "APP-1")

    assert_equal "# hi", @runtime.fs["/workspace/tracker/APP-1/notes.md"]
    assert_match(/no copy was kept/, result["note"])
    assert_equal 0, TaskAsset.count
  end

  test "a named file that is not on the issue is reported, not fetched" do
    result = run_tool(InternalTools::TrackerDownloadAttachments, issue: "APP-1", attachment_ids: [ "7-404" ])

    assert_equal [ [ "7-404", "skipped", "not_found" ] ], result["files"].map { |f| f.values_at("id", "status", "reason") }
    assert_not @youtrack.called?(:download)
  end

  test "attaching uploads each file, shows it in a comment, and does not send the same bytes twice" do
    first = run_tool(InternalTools::TrackerAttachFiles, issue: "APP-1", comment: "Repro attached",
                                                        files: [ { content: "trace", filename: "trace log.txt" } ])
    again = run_tool(InternalTools::TrackerAttachFiles, issue: "APP-1", comment: "Once more",
                                                        files: [ { content: "trace", filename: "trace log.txt" } ])

    assert_equal [ "attached" ], first["files"].pluck("status")
    assert_equal [ "already_on_issue" ], again["files"].pluck("status")
    assert_equal 1, @youtrack.uploads.size
    assert_equal "Repro attached\n\n[trace log.txt](<trace log.txt>)", @youtrack.comments_by_issue[ISSUE_1].first[:text]
    row = TrackerAttachment.find_by!(direction: "exported")
    assert_equal [ ISSUE_1, Digest::SHA256.hexdigest("trace"), TrackerOperation.find_by!(operation: "attach_files").id ],
                 [ row.issue_id, row.content_sha256, row.tracker_operation_id ]
  end

  test "an identical retry in the session replays the first result instead of writing again" do
    params = { issue: "APP-1", files: [ { content: "a", filename: "a.txt" } ] }
    run_tool(InternalTools::TrackerAttachFiles, **params)
    replay = run_tool(InternalTools::TrackerAttachFiles, **params)

    assert replay["replayed"]
    assert_equal 1, @youtrack.uploads.size
  end

  test "a container file is read only after its size is known to fit" do
    @runtime.fs["/workspace/out/report.pdf"] = "%PDF"
    @runtime.fs["/workspace/out/huge.bin"] = "x" * 10
    Trackers::AttachmentExporter.stubs(:max_file_bytes).returns(5)

    message = tool_error(InternalTools::TrackerAttachFiles, issue: "APP-1", files: [ { file_path: "/workspace/out/huge.bin" } ])
    ok = run_tool(InternalTools::TrackerAttachFiles, issue: "APP-1", files: [ { file_path: "/workspace/out/report.pdf" } ])

    assert_match(/larger than/, message)
    assert_equal [ "report.pdf" ], @youtrack.uploads.pluck(:name)
    assert_equal [ "attached" ], ok["files"].pluck("status")
  end

  test "a read-only tracker takes no files" do
    @tracker.update!(access: "read_only")

    message = tool_error(InternalTools::TrackerAttachFiles, issue: "APP-1", files: [ { content: "a", filename: "a.txt" } ])

    assert_match(/read-only/, message)
    assert_empty @youtrack.uploads
  end

  test "a task attachment of another project cannot be sent" do
    other_project = create(:project, company: @project.company, owner: @user)
    board = create(:board, project: other_project)
    other = create(:board_task, board: board, board_column: create(:board_column, board: board))
    asset = other.task_assets.create!(name: "x.txt", file: StringIO.new("x"))

    message = tool_error(InternalTools::TrackerAttachFiles, issue: "APP-1", files: [ { task_asset_id: asset.id } ])

    assert_match(/not found in this project/, message)
  end
end
