# frozen_string_literal: true

module Slack
  # Thin Slack Web API client. App-level credentials come from Settings.slack.*
  # (operator-set once per deployment); per-call tokens are the workspace bot
  # tokens obtained via OAuth. Only the methods Aixle needs are implemented.
  class Client
    class Error < StandardError; end

    BASE = "https://slack.com/api"

    class << self
      # Exchange an OAuth authorization code for a per-workspace bot token.
      # Returns the parsed response: { access_token (xoxb-), bot_user_id, scope,
      # team: { id, name }, ... }.
      def exchange_code(code:, redirect_uri:)
        post_form("oauth.v2.access", {
          client_id: Settings.slack.client_id,
          client_secret: Settings.slack.client_secret,
          code: code,
          redirect_uri: redirect_uri
        })
      end

      # Validate a bot token (and learn its team/bot identity). Raises on failure.
      def auth_test(token:)
        post("auth.test", token: token)
      end

      # Post a message as the bot. `blocks` (Block Kit) and `thread_ts` (reply in
      # a thread) are optional. Requires the chat:write scope.
      def post_message(token:, channel:, text:, thread_ts: nil, blocks: nil)
        post_json("chat.postMessage", token: token, payload: {
          channel: channel, text: text, thread_ts: thread_ts, blocks: blocks
        }.compact)
      end

      # Upload one or more files and share them in a SINGLE Slack message. Each
      # file is `{ filename:, content:, title? }`; `initial_comment` becomes the
      # message text shown above the attachments. Uses Slack's external-upload flow
      # (getUploadURLExternal → POST bytes → completeUploadExternal). Requires the
      # files:write scope.
      def upload_files(token:, channel:, files:, initial_comment: nil, thread_ts: nil)
        uploaded = Array(files).map do |f|
          content  = f[:content].to_s
          filename = f[:filename].presence || "file"
          info = post("files.getUploadURLExternal", token: token,
            params: { filename: filename, length: content.bytesize })
          put_file_bytes(info["upload_url"], filename, content)
          { id: info["file_id"], title: (f[:title].presence || filename) }
        end

        post("files.completeUploadExternal", token: token, params: {
          files: uploaded.to_json,
          channel_id: channel,
          thread_ts: thread_ts,
          initial_comment: initial_comment.presence
        })
      end

      # Download a private file's bytes. `url` is an absolute Slack file URL
      # (url_private / url_private_download); requires the files:read scope. Returns
      # the raw body string (not JSON). When max_bytes is set, the body is streamed
      # and the download is aborted once it exceeds the cap (so a workspace that
      # under-reports a file's size can't OOM the worker).
      def download_file(url:, token:, max_bytes: nil)
        buffer = +"" if max_bytes
        resp = Faraday.new do |f|
          f.request :retry, max: 2, interval: 0.2
          f.adapter Faraday.default_adapter
        end.get(url) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          if max_bytes
            req.options.on_data = proc do |chunk, _overall|
              buffer << chunk
              raise Error, "file_exceeds_size_cap" if buffer.bytesize > max_bytes
            end
          end
        end

        raise Error, "file_download_failed_#{resp.status}" unless resp.success?

        max_bytes ? buffer : resp.body
      end

      private

      # POST raw file bytes to the short-lived upload_url from getUploadURLExternal.
      # Sent as multipart/form-data (field "file"), built by hand to avoid a
      # faraday-multipart dependency.
      def put_file_bytes(upload_url, filename, content)
        boundary = "----aixle#{SecureRandom.hex(12)}"
        body = +""
        body << "--#{boundary}\r\n"
        body << %(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n)
        body << "Content-Type: application/octet-stream\r\n\r\n"
        body << content
        body << "\r\n--#{boundary}--\r\n"

        resp = Faraday.new do |f|
          f.request :retry, max: 2, interval: 0.2
          f.adapter Faraday.default_adapter
        end.post(upload_url) do |req|
          req.headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
          req.body = body
        end
        raise Error, "file_upload_failed_#{resp.status}" unless resp.success?
      end

      def post_form(path, params)
        resp = connection.post(path) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(params.compact)
        end
        parse!(resp)
      end

      def post(path, token:, params: {})
        resp = connection.post(path) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(params.compact)
        end
        parse!(resp)
      end

      def post_json(path, token:, payload:)
        resp = connection.post(path) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["Content-Type"] = "application/json; charset=utf-8"
          req.body = payload.to_json
        end
        parse!(resp)
      end

      def connection
        Faraday.new(url: BASE) do |f|
          f.request :retry, max: 2, interval: 0.2
          f.adapter Faraday.default_adapter
        end
      end

      # Slack always returns HTTP 200 with an { "ok": bool, "error": "..." } body.
      def parse!(resp)
        body = JSON.parse(resp.body.to_s)
        raise Error, (body["error"].presence || "slack_api_error") unless body["ok"]

        body
      rescue JSON::ParserError
        raise Error, "invalid_slack_response"
      end
    end
  end
end
