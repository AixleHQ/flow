# frozen_string_literal: true

# The legal documents the hosted product publishes under /legal, and who has to
# accept each one.
#
# `version` is the date the text last changed. Changing it is what asks people to
# accept again: an acceptance counts only for the version it names, so after a
# bump every user meets the Terms of Use again and every company's admins meet
# the Terms of Service again. Bump it in the same change that edits the text.
#
# Hosted only. A self-hosted or AWS Marketplace installation is the customer's
# own, and these documents describe the service we run.
class LegalDocument
  ACCEPTED_BY = %i[nobody user company].freeze

  attr_reader :key, :title, :version, :accepted_by, :summary

  def initialize(key:, title:, version:, accepted_by:, summary:)
    @key = key
    @title = title
    @version = version
    @accepted_by = accepted_by
    @summary = summary
    freeze
  end

  ALL = [
    new(
      key: "terms_of_service",
      title: "Terms of Service",
      version: "2026-10-31",
      accepted_by: :company,
      summary: "The agreement between Dualboot Partners, LLC and the company that subscribes to Aixle Flow, " \
               "with the Service Level Agreement, Data Processing Addendum and Business Associate Agreement."
    ),
    new(
      key: "terms_of_use",
      title: "Terms of Use",
      version: "2026-10-30",
      accepted_by: :user,
      summary: "The terms every person who signs in to Aixle Flow accepts for their own use of it."
    ),
    new(
      key: "privacy_policy",
      title: "Privacy Policy",
      version: "2026-11-02",
      accepted_by: :nobody,
      summary: "What personal information Aixle Flow collects, why, who receives it, and the choices you have."
    )
  ].freeze

  TERMS_OF_SERVICE = ALL.find { |document| document.key == "terms_of_service" }
  TERMS_OF_USE = ALL.find { |document| document.key == "terms_of_use" }
  PRIVACY_POLICY = ALL.find { |document| document.key == "privacy_policy" }

  class << self
    def find(key) = ALL.find { |document| document.key == key.to_s }

    def accepted = ALL.reject { |document| document.accepted_by == :nobody }

    def published? = Deployment.saas?

    # The versions in force of everything that is accepted, as one string.
    def fingerprint = accepted.map { |document| "#{document.key}@#{document.version}" }.join(" ")

    # Off in the test environment by default, where most suites that sign in
    # under the hosted mode are about something else.
    def acceptance_required? = published? && Settings.legal&.acceptance_required != false

    # What this person must accept before entering `membership`'s company. The
    # Terms of Service are the company's to accept, so only its admins are asked.
    def pending_for(user:, membership:)
      return [] unless acceptance_required?
      return [] if user.nil? || membership.nil?

      pending = []
      pending << TERMS_OF_USE unless LegalAcceptance.current?(TERMS_OF_USE, user: user)
      if membership.admin? && !LegalAcceptance.current?(TERMS_OF_SERVICE, company: membership.company)
        pending << TERMS_OF_SERVICE
      end
      pending
    end
  end

  def updated_on = Date.iso8601(version)
end
