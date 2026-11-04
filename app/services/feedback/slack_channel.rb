# frozen_string_literal: true

module Feedback
  # The operator's feedback channel in Slack, posted to as the bot whose token
  # they configured. An incoming webhook cannot carry files, hence a bot: it
  # needs chat:write and files:write, and has to be a member of the channel (a
  # private one invites it).
  module SlackChannel
    # Answers no later attempt can change: the token, its scopes or the channel
    # stay wrong until an operator fixes them.
    PERMANENT_ERRORS = %w[
      not_authed invalid_auth account_inactive token_revoked token_expired missing_scope
      not_in_channel channel_not_found is_archived no_permission restricted_action
    ].freeze

    module_function

    def configured? = settings.slack_bot_token.present? && settings.slack_channel_id.present?

    def settings = Settings.feedback

    # With files, one upload whose comment is the text, so the text and the
    # files arrive as a single post.
    def post(text, files: [])
      token = settings.slack_bot_token
      channel = settings.slack_channel_id

      if files.any?
        Slack::Client.upload_files(token: token, channel: channel, files: files, initial_comment: text)
      else
        Slack::Client.post_message(token: token, channel: channel, text: text)
      end
    rescue Slack::Client::RateLimited, Faraday::Error => e
      raise DeliveryFailed, "Slack: #{e.message}"
    rescue Slack::Client::Error => e
      raise DeliveryRejected, "Slack refused the post: #{e.message}" if PERMANENT_ERRORS.include?(e.message)

      raise DeliveryFailed, "Slack: #{e.message}"
    end

    # Slack's own control characters: unescaped, a message could ping a channel
    # (`<!channel>`) or dress a link up as something else.
    def escape(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
