# frozen_string_literal: true

# In-memory fake for the Slack boundary. A real object implementing
# Slack::Client's public class-method interface (exchange_code, auth_test,
# post_message, upload_files, download_file) as INSTANCE methods (R3,
# docs/testing.md §4). Callers stub Slack::Client onto one of these via
# SlackTestHelper#stub_slack_client!.
#
# Every method records its call so tests can assert what was sent
# (`oauth_exchanges`, `auth_tests`, `posted_messages`, `uploaded_files`,
# `downloads`) and returns a realistic canned response whose SHAPE matches what
# the real Slack::Client parses out of the Slack Web API — string-keyed hashes
# for the JSON endpoints, a raw String for download_file. That shape equality is
# pinned by test/services/slack/client_contract_test.rb (R4): change a canned
# shape here and the contract test must change with it, or it fails.
class FakeSlackClient
  DEFAULT_TEAM_ID   = "T00000000"
  DEFAULT_TEAM_NAME = "Fake Workspace"
  DEFAULT_BOT_TOKEN = "xoxb-fake-0000000000-bot-token"
  DEFAULT_BOT_USER  = "U0BOTFAKE0"
  DEFAULT_BOT_ID    = "B00000000"
  DEFAULT_SCOPE     = "chat:write,files:read,files:write"
  DEFAULT_FILE_BODY = "fake slack file bytes"
  WORKSPACE_HOST    = "fake-workspace.slack.com"

  attr_reader :oauth_exchanges, :auth_tests, :posted_messages, :uploaded_files, :downloads
  # Let a test tailor the shared canned values (e.g. a specific team_id) without
  # reaching into the response builders.
  attr_accessor :team_id, :team_name, :bot_token, :bot_user_id, :scope, :file_body

  def initialize
    @oauth_exchanges = []
    @auth_tests      = []
    @posted_messages = []
    @uploaded_files  = []
    @downloads       = []
    @seq             = 0

    @team_id     = DEFAULT_TEAM_ID
    @team_name   = DEFAULT_TEAM_NAME
    @bot_token   = DEFAULT_BOT_TOKEN
    @bot_user_id = DEFAULT_BOT_USER
    @scope       = DEFAULT_SCOPE
    @file_body   = DEFAULT_FILE_BODY
  end

  # --- Slack::Client public interface (JSON endpoints return string-keyed hashes) ---

  # oauth.v2.access — the full parsed body. Slack::IntegrationService reads
  # team.id / team.name, access_token, bot_user_id, scope out of it.
  def exchange_code(code:, redirect_uri:)
    @oauth_exchanges << { code: code, redirect_uri: redirect_uri }
    {
      "ok"           => true,
      "access_token" => bot_token,
      "token_type"   => "bot",
      "scope"        => scope,
      "bot_user_id"  => bot_user_id,
      "app_id"       => "A00000000",
      "team"         => { "id" => team_id, "name" => team_name },
      "enterprise"   => nil,
      "authed_user"  => { "id" => "U00USER000" }
    }
  end

  # auth.test — identity of a bot token. Not consumed by the four production
  # callers today, but part of the adapter's public interface, so the fake and
  # its contract test cover it.
  def auth_test(token:)
    @auth_tests << { token: token }
    {
      "ok"      => true,
      "url"     => "https://#{WORKSPACE_HOST}/",
      "team"    => team_name,
      "user"    => "aixle",
      "team_id" => team_id,
      "user_id" => bot_user_id,
      "bot_id"  => DEFAULT_BOT_ID
    }
  end

  # chat.postMessage — { ok, channel, ts, message }. Slack::Notifier only checks
  # that this does not raise (truthy return), so the exact shape matters only for
  # the contract pin.
  def post_message(token:, channel:, text: nil, thread_ts: nil, blocks: nil)
    ts = next_ts
    @posted_messages << {
      token: token, channel: channel, text: text, thread_ts: thread_ts, blocks: blocks
    }
    {
      "ok"      => true,
      "channel" => channel,
      "ts"      => ts,
      "message" => {
        "type"    => "message",
        "subtype" => "bot_message",
        "text"    => text.to_s,
        "ts"      => ts,
        "bot_id"  => DEFAULT_BOT_ID
      }
    }
  end

  # files.completeUploadExternal — the body the real client returns after the
  # getUploadURLExternal -> PUT bytes -> completeUploadExternal flow.
  def upload_files(token:, channel:, files:, initial_comment: nil, thread_ts: nil)
    uploaded = Array(files).map do |f|
      { filename: f[:filename], title: f[:title], content: f[:content] }
    end
    @uploaded_files << {
      token: token, channel: channel, initial_comment: initial_comment,
      thread_ts: thread_ts, files: uploaded
    }
    {
      "ok"    => true,
      "files" => uploaded.each_with_index.map do |f, i|
        filename = f[:filename].presence || "file"
        id       = format("F%08dFAKE", i)
        {
          "id"        => id,
          "name"      => filename,
          "title"     => (f[:title].presence || filename),
          "mimetype"  => "text/plain",
          "size"      => f[:content].to_s.bytesize,
          "permalink" => "https://#{WORKSPACE_HOST}/files/#{id}"
        }
      end
    }
  end

  # File download — the raw body String (not JSON). Slack::FileIngestor writes it
  # straight into an AssetVersion.
  def download_file(url:, token:, max_bytes: nil)
    @downloads << { url: url, token: token, max_bytes: max_bytes }
    file_body.dup
  end

  # --- Convenience readers for callers migrating in Stage B ---

  def last_posted_message
    posted_messages.last
  end

  def last_uploaded_files
    uploaded_files.last
  end

  def last_download
    downloads.last
  end

  private

  # Slack message timestamps look like "1700000000.000123"; monotonic per fake so
  # recorded messages stay distinguishable.
  def next_ts
    @seq += 1
    "1700000000.#{format('%06d', @seq)}"
  end
end
