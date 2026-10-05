# frozen_string_literal: true

module Teams
  # The Bot Connector REST calls the bot makes, against the serviceUrl of the
  # conversation it answers (docs/design/teams-integration.md §5.4). Each call is
  # handed a reference recorded from an authenticated activity: the serviceUrl,
  # the conversation, and the two accounts.
  module ConnectorClient
    # One automatic retry on a throttle or a server error; anything longer is the
    # caller's to schedule, so a request never sleeps through Teams' 15 s budget.
    MAX_RETRY_AFTER = 5

    module_function

    def reply(reference, activity)
      post(reference, "#{conversation_path(reference)}/activities/#{escape(reference.fetch('activity_id'))}", activity)
    end

    def send_message(reference, activity)
      post(reference, "#{conversation_path(reference)}/activities", activity)
    end

    def update(reference, activity_id, activity)
      request(reference, :put, "#{conversation_path(reference)}/activities/#{escape(activity_id)}",
              stamped(reference, activity).merge(id: activity_id))
    end

    def delete(reference, activity_id)
      request(reference, :delete, "#{conversation_path(reference)}/activities/#{escape(activity_id)}")
    end

    # A new thread in a channel: Teams has no "post to channel" call, only "start
    # a conversation" whose first activity becomes the thread's root.
    def start_thread(reference, channel_id:, activity:)
      request(reference, :post, "v3/conversations", {
        isGroup: true, bot: reference.fetch("bot"), tenantId: reference.fetch("tenant_id"),
        activity: stamped(reference, activity).except(:conversation),
        channelData: { channel: { id: channel_id }, tenant: { id: reference.fetch("tenant_id") } }
      })
    end

    # The team's Microsoft 365 group id, which Graph needs, and its name.
    def team(reference, team_id)
      request(reference, :get, "v3/teams/#{escape(team_id)}")
    end

    def channels(reference, team_id)
      request(reference, :get, "v3/teams/#{escape(team_id)}/conversations").fetch("conversations", [])
    end

    def member(reference, member_id)
      request(reference, :get, "#{conversation_path(reference)}/members/#{escape(member_id)}")
    end

    def post(reference, path, activity)
      request(reference, :post, path, stamped(reference, activity))
    end

    # The Connector refuses an activity without `from` (400 MissingProperty); the
    # SDKs stamp every outgoing one with the reversed reference, and so does this.
    def stamped(reference, activity)
      { from: reference.fetch("bot"), recipient: reference["user"],
        conversation: { id: reference.fetch("conversation_id") } }.compact.merge(activity.symbolize_keys)
    end

    def conversation_path(reference)
      "v3/conversations/#{escape(reference.fetch('conversation_id'))}"
    end

    # Ids carry `:`, `;`, `@` and, in some channels, `|`.
    def escape(id) = ERB::Util.url_encode(id.to_s)

    def request(reference, method, path, body = nil, retried: false)
      base = reference.fetch("service_url").to_s
      raise Error, "serviceUrl #{base.inspect} is not a Bot Framework host" unless Config.service_url_allowed?(base)

      response = connection(base).run_request(method, path, body&.to_json, headers)
      if retryable?(response) && !retried
        sleep_for = response.headers["Retry-After"].to_i.clamp(0, MAX_RETRY_AFTER)
        sleep(sleep_for) if sleep_for.positive?
        TokenService.forget!(Config.home_tenant_id) if response.status == 401
        return request(reference, method, path, body, retried: true)
      end
      raise Error.new("Bot Connector #{method.upcase} #{path}: HTTP #{response.status} #{response.body.to_s.truncate(300)}",
                      status: response.status, retry_after: response.headers["Retry-After"]&.to_i) unless response.success?

      response.body.to_s.empty? ? {} : JSON.parse(response.body)
    end

    def retryable?(response)
      response.status == 401 || response.status == 429 || response.status >= 500
    end

    def headers
      { "Authorization" => "Bearer #{TokenService.bot_token}", "Content-Type" => "application/json; charset=utf-8" }
    end

    def connection(base)
      Faraday.new(url: base.end_with?("/") ? base : "#{base}/") do |f|
        f.options.open_timeout = 5
        f.options.timeout = 10
      end
    end
  end
end
