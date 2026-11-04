# frozen_string_literal: true

module Feedback
  # Tells the feedback channel a company was created, and by which path, so the
  # team sees who is joining and can reach out early. Wherever that channel is
  # configured, which is also what keeps it quiet everywhere else.
  class NewCompanyAnnouncement
    SOURCES = {
      "signup" => "Self-serve signup (/workspace/new)",
      "marketplace" => "AWS Marketplace signup",
      "admin" => "Admin"
    }.freeze

    # `by` is whoever created it: the person signing up, or the operator in the
    # admin. `invited` is the first admin that operator invited, if any.
    #
    # Never raises: the company exists by now, and its announcement failing must
    # not turn the signup or the admin's form into an error.
    def self.later(company, source:, by:, invited: nil)
      return unless SlackChannel.configured?

      SlackPostJob.perform_later(new(company, source: source, by: by, invited: invited).text)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { company_id: company&.id, source: source })
    end

    def initialize(company, source:, by:, invited: nil)
      @company = company
      @source = SOURCES.fetch(source)
      @by = by
      @invited = invited
    end

    def text
      fields = {
        "Source" => @source,
        "Tenant ID" => @company.id,
        "Domain" => @company.email_domain,
        "Created by" => @by && "#{@by.name} (#{@by.email})",
        "First admin invited" => @invited,
        "Created" => @company.created_at.utc.strftime("%Y-%m-%d %H:%M UTC")
      }.compact_blank
      lines = fields.map { |label, value| "*#{label}:* #{SlackChannel.escape(value)}" }
      [ "*🆕 New tenant: #{SlackChannel.escape(@company.name)}*", *lines ].join("\n")
    end
  end
end
