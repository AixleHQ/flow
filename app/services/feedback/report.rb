# frozen_string_literal: true

module Feedback
  # What every destination shows of a submission: a title, and who sent it from where.
  class Report
    TITLE_MAX = 80

    def initialize(submission)
      @submission = submission
    end

    def title
      first_line = @submission.message.lines.map(&:strip).find(&:present?).to_s
      "#{kind_label}: #{first_line.truncate(TITLE_MAX)}"
    end

    def kind_label = @submission.kind.text

    # Label => value, in display order, without the ones that are empty.
    def fields
      {
        "Type" => kind_label,
        "From" => sender,
        "Company" => @submission.company.name,
        "Page" => @submission.page_url,
        "Version" => @submission.app_version,
        "Sent" => @submission.created_at.utc.strftime("%Y-%m-%d %H:%M UTC"),
        "Files" => @submission.attachments.map(&:name).join(", ")
      }.compact_blank
    end

    private

    def sender
      user = @submission.user
      user ? "#{user.name} (#{user.email})" : "a deleted user"
    end
  end
end
