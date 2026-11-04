# frozen_string_literal: true

module Feedback
  # Posts each submission, its files included, to the feedback channel.
  class SlackDestination
    def self.configured? = SlackChannel.configured?

    def initialize(submission)
      @submission = submission
    end

    def deliver
      return if @submission.slack_delivered_at

      SlackChannel.post(text, files: files)
      @submission.update!(slack_delivered_at: Time.current)
    end

    private

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

    def escape(value) = SlackChannel.escape(value)
  end
end
