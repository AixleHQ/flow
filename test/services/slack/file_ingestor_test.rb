# frozen_string_literal: true

require "test_helper"

module Slack
  class FileIngestorTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @integration = Integration.create!(
        provider: :slack, company: @user.companies.first, project: @project, connected_by: @user,
        name: "Acme", status: :active
      )
      @integration.update!(credentials_data: { "bot_token" => "xoxb-1", "team_id" => "T1" })
      stub_slack_client!
    end

    def ingestor
      Slack::FileIngestor.new(integration: @integration, project: @project)
    end

    def file(id: "F1", name: "spec.pdf", size: 100, url: "https://files.slack.com/x")
      { "id" => id, "name" => name, "size" => size, "url_private" => url, "mimetype" => "application/pdf" }
    end

    test "downloads a file with the bot token and stores it as a project asset" do
      fake_slack.file_body = "PDFBYTES"

      ids = nil
      assert_difference -> { Asset.count } => 1, -> { AssetVersion.count } => 1 do
        ids = ingestor.ingest([ file ])
      end

      asset = Asset.find(ids.first)
      assert_equal "Project", asset.scope_type
      assert_equal @project.id, asset.scope_id
      assert_equal @user, asset.created_by
      assert_equal "spec.pdf", asset.name
      assert asset.versions.first.slack?
      assert_equal "xoxb-1", fake_slack.last_download[:token]
    end

    test "skips files over the size cap without downloading" do
      assert_no_difference -> { Asset.count } do
        assert_equal [], ingestor.ingest([ file(size: 60 * 1024 * 1024) ])
      end
      assert_equal [], fake_slack.downloads
    end

    test "skips a file whose download fails and keeps the rest" do
      # Per-file error injection (first download raises, second succeeds) — a
      # sequence the canonical fake cannot express, so we drive it through the
      # fake's own download_file while still routing Slack::Client via the seam.
      fake_slack.stubs(:download_file).raises(Slack::Client::Error.new("file_not_found")).then.returns("OK")

      ids = ingestor.ingest([ file(id: "F1", name: "bad.txt"), file(id: "F2", name: "good.txt") ])
      assert_equal 1, ids.size
    end

    test "disambiguates a clashing asset name across messages" do
      fake_slack.file_body = "BYTES"

      first = ingestor.ingest([ file(id: "F1", name: "dup.txt") ])
      second = ingestor.ingest([ file(id: "F2", name: "dup.txt") ])

      assert_not_equal first.first, second.first
      assert_equal 2, Asset.where(folder: "slack").count
    end

    test "skips a file whose URL is not a Slack host (SSRF guard)" do
      assert_equal [], ingestor.ingest([ file(url: "https://169.254.169.254/latest/meta-data") ])
      assert_equal [], fake_slack.downloads
    end

    test "returns [] when the install has no bot token" do
      @integration.update!(credentials_data: {})
      assert_equal [], ingestor.ingest([ file ])
      assert_equal [], fake_slack.downloads
    end
  end
end
