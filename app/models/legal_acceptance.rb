# frozen_string_literal: true

# Evidence that a person accepted one version of a legal document (LegalDocument).
# Append-only: accepting a new version adds a row and leaves the old ones alone.
#
# A row names who accepted and for which company in its own columns, because it
# outlives both: deleting the person or the company nullifies the reference and
# keeps the evidence.
class LegalAcceptance < ApplicationRecord
  # When and from where a box was ticked. Taken from the request that ticked it,
  # which for a stranger's signup is not the one that records it: their answers
  # wait in an emailed link (WorkspaceSignupTicket) until it is opened.
  Evidence = Data.define(:accepted_at, :ip_address, :user_agent) do
    def self.from(request)
      new(accepted_at: Time.current, ip_address: request.remote_ip,
          user_agent: request.user_agent.to_s.truncate(500).presence)
    end
  end

  belongs_to :user, optional: true
  belongs_to :company, optional: true

  validates :document, inclusion: { in: -> { LegalDocument.accepted.map(&:key) } }
  validates :version, :accepted_at, presence: true
  validates :company, presence: true, on: :create, if: -> { document == LegalDocument::TERMS_OF_SERVICE.key }

  class << self
    def current?(document, user: nil, company: nil)
      scope = where(document: document.key, version: document.version)
      scope = scope.where(company: company) if company
      scope = scope.where(user: user) if user
      scope.exists?
    end

    # The company is required for the Terms of Service and ignored for the Terms
    # of Use, which bind the person wherever they work.
    def record!(document, user:, evidence:, company: nil)
      company = nil unless document.accepted_by == :company
      create!(
        document: document.key,
        version: document.version,
        user: user,
        user_email: user.email,
        company: company,
        company_name: company&.name,
        company_email_domain: company&.email_domain,
        accepted_at: evidence.accepted_at,
        ip_address: evidence.ip_address,
        user_agent: evidence.user_agent
      )
    end
  end
end
