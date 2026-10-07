# frozen_string_literal: true

require "test_helper"

# Files between Teams and a project (docs/design/teams-integration.md §8.5):
# in from each kind of conversation, out to each, and the links that work
# without a token kept only as long as they are needed.
class Teams::FilesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  GRAPH = "https://graph.microsoft.com/v1.0"
  GROUP = "1b22f251-0000-4000-8000-000000000001"
  DOWNLOAD = "https://contoso-my.sharepoint.com/personal/olo/_layouts/15/download.aspx?UniqueId=u1&tempauth=secret"

  setup do
    with_teams_enabled
    resolve_hosts_publicly!
    stub_teams_token!
    stub_teams_token!(tenant: TEAMS_CUSTOMER_TENANT, token: "graph-token")
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @integration = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                       status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT, "file_access" => true })
    @endpoint = create(:webhook_endpoint, slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}", provider: :teams,
                                          verification_strategy: :none, secret: nil, company: @company,
                                          config: { "integration_id" => @integration.id })
    @channel = ChatConversation.record_teams!(integration: @integration, activity: teams_activity)
    @channel.update!(team_aad_group_id: GROUP)
    @workflow = create(:workflow, scope: @project)
    create(:step, workflow: @workflow, allow_non_interactive: true)
  end

  def direct_activity
    teams_activity(conversation_type: "personal", mention: false, attachments: [
      { "contentType" => "application/vnd.microsoft.teams.file.download.info", "name" => "brief.pdf",
        "content" => { "downloadUrl" => DOWNLOAD, "uniqueId" => "u1", "fileType" => "pdf" } }
    ])
  end

  def receive(activity)
    ReceivedWebhook.create!(webhook_endpoint: @endpoint, idempotency_key: SecureRandom.hex, event_type: "teams",
                            raw_payload: activity)
  end

  test "a 1:1 file becomes a project asset, and no link to it outlives the message" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                             filter_predicate: { "provider" => "teams" })
    ChatConversation.record_teams!(integration: @integration, activity: direct_activity)
    stub_request(:get, DOWNLOAD).to_return(status: 200, body: "%PDF-1.7 brief")
    received = receive(direct_activity)
    handed = nil
    WorkflowService.expects(:enqueue).with { |**args| handed = args[:input_asset_ids] }.returns(build(:workflow_run))

    Webhooks::ProcessEventJob.perform_now(received.id)

    asset = Asset.last
    assert_equal [ asset.id ], handed
    assert_equal [ "brief.pdf", "teams", "teams" ], [ asset.name, asset.folder, asset.latest_version.source ]
    assert_equal "%PDF-1.7 brief", asset.latest_version.file.read
    assert_nil TriggerEvent.sole.data["file_refs"]
    assert_equal({ "uniqueId" => "u1", "fileType" => "pdf" }, received.reload.raw_payload.dig("attachments", 0, "content"))
  end

  test "a link that is not Microsoft 365's is never fetched" do
    assert_raises(Teams::Error) { Teams::Files.download_link("https://169.254.169.254/latest/meta-data") }
    assert_raises(Teams::Error) { Teams::Files.download_link("https://contoso.sharepoint.com.evil.test/file") }
  end

  test "a channel message's files are read from Graph and fetched through the share link" do
    activity = teams_activity.deep_merge("id" => "1700000000003", "attachments" => [
      # What Teams really sends the bot: no trace of the file in the HTML.
      { "contentType" => "text/html", "content" => "<p><span itemtype=\"http://schema.skype.com/Mention\">Aixle Flow</span>&nbsp;deploy</p>" }
    ])
    reply = "#{GRAPH}/teams/#{GROUP}/channels/19%3Aabc%40thread.tacv2/messages/1700000000001/replies/1700000000003"
    shared = "https://contoso.sharepoint.com/sites/Sales/Shared%20Documents/Onboarding/plan.docx"
    stub_request(:get, reply).to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
      attachments: [ { contentType: "reference", contentUrl: shared, name: "plan.docx" } ], body: { content: "" }
    }.to_json)
    share = "u!#{Base64.urlsafe_encode64(shared, padding: false)}"
    stub_request(:get, "#{GRAPH}/teams/#{GROUP}/channels/19%3Aabc%40thread.tacv2/filesFolder")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "F1", parentReference: { driveId: "b!sales" } }.to_json)
    stub_request(:get, "#{GRAPH}/shares/#{share}/driveItem?%24select=id,parentReference")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "I1", parentReference: { driveId: "b!sales" } }.to_json)
    stub_request(:get, "#{GRAPH}/shares/#{share}/driveItem/content")
      .to_return(status: 302, headers: { "Location" => "https://contoso.sharepoint.com/_layouts/15/download.aspx?t=1" })
    stub_request(:get, "https://contoso.sharepoint.com/_layouts/15/download.aspx?t=1").to_return(status: 200, body: "DOCX")

    data = Chat::TeamsProvider.normalize(@endpoint, activity)[:data]
    event = TriggerEvent.new(data: data.stringify_keys)

    assert_equal [ "plan.docx" ], data["files"].pluck("name")
    assert_equal 1, Chat::TeamsProvider.ingest_files(event, @project).size
    assert_equal "DOCX", Asset.last.latest_version.file.read

    # A message can link any file; one outside the team's own files is not read.
    stub_request(:get, "#{GRAPH}/shares/#{share}/driveItem?%24select=id,parentReference")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "I2", parentReference: { driveId: "b!hr" } }.to_json)
    assert_no_difference -> { Asset.count } do
      assert_empty Chat::TeamsProvider.ingest_files(event, @project)
    end

    @integration.update!(settings: @integration.settings.merge("file_access" => false))
    assert_empty Chat::TeamsProvider.ingest_files(event, @project)
  end

  test "sending files to a channel puts them in its Aixle folder and links them in the thread" do
    folder = { id: "F1", parentReference: { driveId: "b!drive" } }
    stub_request(:get, "#{GRAPH}/teams/#{GROUP}/channels/19%3Aabc%40thread.tacv2/filesFolder")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: folder.to_json)
    upload = stub_request(:put, "#{GRAPH}/drives/b%21drive/items/F1:/Aixle/report.csv:/content?@microsoft.graph.conflictBehavior=rename")
             .with(body: "a,b\n").to_return(status: 201, headers: { "Content-Type" => "application/json" },
                                             body: { name: "report.csv", webUrl: "https://contoso.sharepoint.com/report.csv" }.to_json)
    linked = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities")
             .with(body: hash_including("text" => "📎 [report.csv](https://contoso.sharepoint.com/report.csv)"))
             .to_return(status: 201, body: { id: "5" }.to_json)

    sent = Teams::FileSender.deliver(@channel, thread_id: "1700000000001", files: [ { filename: "report.csv", content: "a,b\n" } ],
                                               project: @project, user: @user, origin_conversation: @channel.external_id)

    assert_requested upload
    assert_requested linked
    assert_equal [ { name: "report.csv", delivered: "uploaded", url: "https://contoso.sharepoint.com/report.csv" } ], sent
  end

  test "files for a channel the run did not come from are linked, not written there" do
    stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities")
      .to_return(status: 201, body: { id: "5" }.to_json)

    sent = Teams::FileSender.deliver(@channel, thread_id: "1700000000001", files: [ { filename: "report.csv", content: "x" } ],
                                               project: @project, user: @user, origin_conversation: "19:elsewhere@thread.tacv2")

    assert_equal "linked", sent.sole[:delivered]
    assert_not_requested :put, %r{graph.microsoft.com}
  end

  test "a 1:1 file waits for the person's consent, then lands in their OneDrive" do
    direct = ChatConversation.record_teams!(integration: @integration, activity: direct_activity)
    chat = "#{TEAMS_SERVICE_URL}v3/conversations/a%3A1personal/activities"
    consent = nil
    stub_request(:post, chat).with { |request| consent ||= JSON.parse(request.body)["attachments"]&.first }
                             .to_return(status: 201, body: { id: "card-1" }.to_json)

    Teams::FileSender.deliver(direct, thread_id: nil, files: [ { filename: "report.csv", content: "a,b\n" } ], project: @project, user: @user)

    assert_equal [ "application/vnd.microsoft.teams.card.file.consent", 4 ], [ consent["contentType"], consent.dig("content", "sizeInBytes") ]
    context = Teams::FileSender.consent_verifier.verified(consent.dig("content", "acceptContext", "token"))
    assert_equal direct.id, context["conversation_id"]
    upload = { "uploadUrl" => "https://contoso-my.sharepoint.com/upload/1", "contentUrl" => "https://contoso-my.sharepoint.com/report.csv",
               "name" => "report.csv", "uniqueId" => "u9", "fileType" => "csv" }
    put = stub_request(:put, "https://contoso-my.sharepoint.com/upload/1").with(body: "a,b\n", headers: { "Content-Range" => "bytes 0-3/4" })
                                                                         .to_return(status: 201)
    info = stub_request(:post, chat).with(body: hash_including("attachments" => [ hash_including("contentType" => "application/vnd.microsoft.teams.card.file.info") ]))
                                    .to_return(status: 201, body: { id: "2" }.to_json)
    removed = stub_request(:delete, "#{chat}/card-1").to_return(status: 200)

    Teams::FileConsentJob.perform_now(direct.id, context["asset_id"], upload, "card-1")

    assert_requested put
    assert_requested info
    assert_requested removed
  end

  test "group chat files are shared as links to the project's files" do
    group = ChatConversation.record_teams!(integration: @integration, activity: teams_activity(conversation_type: "groupChat").deep_merge(
      "conversation" => { "id" => "19:chat@thread.v2" }
    ))
    linked = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Achat%40thread.v2/activities")
             .with(body: hash_including("text" => %r{report\.csv — in \[the project's files in Aixle\]\(.*/assets\)}))
             .to_return(status: 201, body: { id: "1" }.to_json)

    sent = Teams::FileSender.deliver(group, thread_id: nil, files: [ { filename: "report.csv", content: "x" } ], project: @project, user: @user)

    assert_requested linked
    assert_equal "linked", sent.sole[:delivered]
  end
end
