# frozen_string_literal: true

require "test_helper"

module Slack
  # Contract test (R4, docs/testing.md §4): pins FakeSlackClient's canned shapes to
  # what the real Slack::Client parses out of the Slack Web API. Each case drives
  # the adapter against WebMock stubs carrying realistic Slack JSON and asserts the
  # adapter's parsed return equals the shape the fake hands back — so the fake can
  # never silently drift from reality. The stubbed payloads are sourced from the
  # fake itself, making FakeSlackClient the single source of truth for the shape.
  class ClientContractTest < ActiveSupport::TestCase
    BOT_TOKEN = "xoxb-1"
    API = "https://slack.com/api"

    setup { @fake = FakeSlackClient.new }

    def json(body)
      { status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json }
    end

    # --- oauth.v2.access -------------------------------------------------------

    test "exchange_code parses the oauth.v2.access body into the fake's shape" do
      expected = @fake.exchange_code(code: "auth-code", redirect_uri: "https://app.test/slack/cb")
      stub = stub_request(:post, "#{API}/oauth.v2.access")
        .with(body: hash_including("code" => "auth-code", "redirect_uri" => "https://app.test/slack/cb"))
        .to_return(json(expected))

      actual = Slack::Client.exchange_code(code: "auth-code", redirect_uri: "https://app.test/slack/cb")

      assert_equal expected, actual
      assert_equal "T00000000", actual.dig("team", "id")
      assert_equal "Fake Workspace", actual.dig("team", "name")
      assert_equal "xoxb-fake-0000000000-bot-token", actual["access_token"]
      assert_requested stub
    end

    test "exchange_code raises Slack::Client::Error on an ok:false body" do
      stub_request(:post, "#{API}/oauth.v2.access")
        .to_return(json(ok: false, error: "invalid_code"))

      error = assert_raises(Slack::Client::Error) do
        Slack::Client.exchange_code(code: "bad", redirect_uri: "https://app.test/slack/cb")
      end
      assert_match(/invalid_code/, error.message)
    end

    # --- auth.test -------------------------------------------------------------

    test "auth_test sends the bearer token and parses into the fake's shape" do
      expected = @fake.auth_test(token: BOT_TOKEN)
      stub = stub_request(:post, "#{API}/auth.test")
        .with(headers: { "Authorization" => "Bearer #{BOT_TOKEN}" })
        .to_return(json(expected))

      actual = Slack::Client.auth_test(token: BOT_TOKEN)

      assert_equal expected, actual
      assert_equal "T00000000", actual["team_id"]
      assert_equal "U0BOTFAKE0", actual["user_id"]
      assert_requested stub
    end

    # --- chat.postMessage ------------------------------------------------------

    test "post_message posts JSON and parses into the fake's shape" do
      expected = @fake.post_message(token: BOT_TOKEN, channel: "C1", text: "hi", thread_ts: "5.5")
      stub = stub_request(:post, "#{API}/chat.postMessage")
        .with(
          headers: { "Authorization" => "Bearer #{BOT_TOKEN}", "Content-Type" => "application/json; charset=utf-8" },
          body: hash_including("channel" => "C1", "text" => "hi", "thread_ts" => "5.5")
        )
        .to_return(json(expected))

      actual = Slack::Client.post_message(token: BOT_TOKEN, channel: "C1", text: "hi", thread_ts: "5.5")

      assert_equal expected, actual
      assert_equal "C1", actual["channel"]
      assert actual["ts"].present?
      assert_requested stub
    end

    test "post_message raises Slack::Client::Error on an ok:false body" do
      stub_request(:post, "#{API}/chat.postMessage")
        .to_return(json(ok: false, error: "channel_not_found"))

      error = assert_raises(Slack::Client::Error) do
        Slack::Client.post_message(token: BOT_TOKEN, channel: "C1", text: "hi")
      end
      assert_match(/channel_not_found/, error.message)
    end

    # --- files: getUploadURLExternal -> PUT bytes -> completeUploadExternal ----

    test "upload_files runs the external-upload flow and returns completeUpload's shape" do
      files = [ { filename: "a.rb", content: "puts 1", title: "Script" } ]
      expected = @fake.upload_files(token: BOT_TOKEN, channel: "C1", files: files,
        initial_comment: "hi", thread_ts: "5.5")
      upload_url = "https://files.slack.com/upload/v1/abc123"

      get_url = stub_request(:post, "#{API}/files.getUploadURLExternal")
        .with(headers: { "Authorization" => "Bearer #{BOT_TOKEN}" },
              body: hash_including("filename" => "a.rb", "length" => "6"))
        .to_return(json(ok: true, upload_url: upload_url, file_id: "F00000000FAKE"))
      put_bytes = stub_request(:post, upload_url).to_return(status: 200, body: "OK")
      complete = stub_request(:post, "#{API}/files.completeUploadExternal")
        .with(body: hash_including("channel_id" => "C1", "thread_ts" => "5.5", "initial_comment" => "hi"))
        .to_return(json(expected))

      actual = Slack::Client.upload_files(token: BOT_TOKEN, channel: "C1", files: files,
        initial_comment: "hi", thread_ts: "5.5")

      assert_equal expected, actual
      assert actual["ok"]
      assert_equal "a.rb", actual.dig("files", 0, "name")
      assert_requested get_url
      assert_requested put_bytes
      assert_requested complete
    end

    # --- file download ---------------------------------------------------------

    test "download_file returns the raw body the fake hands back" do
      url = "https://files.slack.com/files-pri/T1-F1/spec.pdf"
      expected = @fake.download_file(url: url, token: BOT_TOKEN)
      stub = stub_request(:get, url)
        .with(headers: { "Authorization" => "Bearer #{BOT_TOKEN}" })
        .to_return(status: 200, body: expected)

      actual = Slack::Client.download_file(url: url, token: BOT_TOKEN)

      assert_equal expected, actual
      assert_kind_of String, actual
      assert_requested stub
    end

    test "download_file aborts when the streamed body exceeds max_bytes" do
      url = "https://files.slack.com/files-pri/T1-F2/big.bin"
      stub_request(:get, url).to_return(status: 200, body: "x" * 100)

      error = assert_raises(Slack::Client::Error) do
        Slack::Client.download_file(url: url, token: BOT_TOKEN, max_bytes: 10)
      end
      assert_match(/file_exceeds_size_cap/, error.message)
    end

    test "download_file raises Slack::Client::Error on a non-2xx response" do
      url = "https://files.slack.com/files-pri/T1-F3/gone.pdf"
      stub_request(:get, url).to_return(status: 404, body: "not found")

      error = assert_raises(Slack::Client::Error) do
        Slack::Client.download_file(url: url, token: BOT_TOKEN)
      end
      assert_match(/file_download_failed_404/, error.message)
    end
  end
end
