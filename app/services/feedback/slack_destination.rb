# frozen_string_literal: true

module Feedback
  # Posts each submission, its files included, to one Slack channel as the bot
  # whose token the operator configured. An incoming webhook cannot carry files,
  # hence a bot: it needs chat:write and files:write, and has to be a member of
  # the channel (a private one invites it).
  class SlackDestination
    # Answers no later attempt can change: the token, its scopes or the channel
    # stay wrong until an operator fixes them.
    PERMANENT_ERRORS = %w[
      not_authed invalid_auth account_inactive token_revoked token_expired missing_scope
      not_in_channel channel_not_found is_archived no_permission restricted_action
    ].freeze

    def self.configured? = settings.slack_bot_token.present? && settings.slack_channel_id.present?

    def self.settings = Settings.feedback

    def initialize(submission)
      @submission = submission
    end

    def deliver
      return if @submission.slack_delivered_at

      post
      @submission.update!(slack_delivered_at: Time.current)
    end

    private

    # With files, one upload whose comment is the message, so the text and the
    # files arrive as a single post.
    def post
      settings = self.class.settings
      token = settings.slack_bot_token
      channel = settings.slack_channel_id

      if @submission.attachments.any?
        Slack::Client.upload_files(token: token, channel: channel, files: files, initial_comment: text)
      else
        Slack::Client.post_message(token: token, channel: channel, text: text)
      end
    rescue Slack::Client::RateLimited, Faraday::Error => e
      raise DeliveryFailed, "Slack: #{e.message}"
    rescue Slack::Client::Error => e
      raise DeliveryRejected, "Slack refused the feedback: #{e.message}" if PERMANENT_ERRORS.include?(e.message)

      raise DeliveryFailed, "Slack: #{e.message}"
    end

    def files
      @submission.attachments.map do |attachment|
        { filename: attachment.name, content: attachment.file.download(&:read) }
      end
    end

    def text
      report = Report.new(@submission)
      fields = report.fields.except("Files").map { |label, value| "*#{label}:* #{escape(value)}" }
      [ "*#{escape(report.title)}*", quote(@submission.message), *fields ].join("\n")
    end

    def quote(message)
      escape(message).split("\n").map { |line| "> #{line}" }.join("\n")
    end

    # Slack's own control characters: unescaped, a message could ping a channel
    # (`<!channel>`) or dress a link up as something else.
    def escape(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
