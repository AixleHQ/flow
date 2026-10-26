# frozen_string_literal: true

require "test_helper"

class Teams::FileConsentJobTest < ActiveJob::TestCase
  UPLOAD = { "uploadUrl" => "https://contoso-my.sharepoint.com/upload/1", "contentUrl" => "https://contoso-my.sharepoint.com/report.csv",
             "name" => "report.csv", "uniqueId" => "u9", "fileType" => "csv" }.freeze

  setup do
    with_teams_enabled
    resolve_hosts_publicly!
    stub_teams_token!
    user = create(:user, :with_company)
    integration = Integration.create!(provider: :teams, company: user.companies.first, connected_by: user,
                                      name: "Contoso", status: :active)
    @direct = ChatConversation.record_teams!(integration: integration,
                                             activity: teams_activity(conversation_type: "personal", mention: false))
    @asset = create(:asset_version, :with_file, asset: create(:asset, :with_company_scope)).asset
    @chat = "#{TEAMS_SERVICE_URL}v3/conversations/a%3A1personal/activities"
  end

  def accept
    Teams::FileConsentJob.perform_now(@direct.id, @asset.id, UPLOAD, "card-1")
  end

  test "a file the chat refuses is given up, not tried again" do
    stub_request(:put, UPLOAD["uploadUrl"]).to_return(status: 404)

    assert_no_enqueued_jobs(only: Teams::FileConsentJob) { accept }
    assert_not_requested :post, @chat

    stub_request(:put, UPLOAD["uploadUrl"]).to_return(status: 201)
    refused = stub_request(:post, @chat)
              .to_return(status: 403, body: { error: { code: "BotNotInConversationRoster" } }.to_json)

    assert_no_enqueued_jobs(only: Teams::FileConsentJob) { accept }
    assert_requested refused
    assert_not_requested :delete, "#{@chat}/card-1"
  end

  test "a throttle or an outage is tried again later" do
    stub_request(:put, UPLOAD["uploadUrl"]).to_timeout

    assert_enqueued_with(job: Teams::FileConsentJob, args: [ @direct.id, @asset.id, UPLOAD, "card-1" ]) { accept }

    stub_request(:put, UPLOAD["uploadUrl"]).to_return(status: 201)
    stub_request(:post, @chat).to_return(status: 503)

    assert_enqueued_with(job: Teams::FileConsentJob, args: [ @direct.id, @asset.id, UPLOAD, "card-1" ]) { accept }
  end
end
