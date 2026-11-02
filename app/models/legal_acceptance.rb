# frozen_string_literal: true

# Evidence that a person accepted one version of a legal document (LegalDocument).
# Append-only: accepting a new version adds a row and leaves the old ones alone.
class LegalAcceptance < ApplicationRecord
  # Nil once the person has been permanently deleted; a company's acceptance
  # stays in force without them.
  belongs_to :user, optional: true
  belongs_to :company, optional: true

  validates :document, inclusion: { in: -> { LegalDocument.accepted.map(&:key) } }
  validates :version, :accepted_at, presence: true
  validates :company, presence: true, if: -> { document == LegalDocument::TERMS_OF_SERVICE.key }

  class << self
    def current?(document, user: nil, company: nil)
      scope = where(document: document.key, version: document.version)
      scope = scope.where(company: company) if company
      scope = scope.where(user: user) if user
      scope.exists?
    end

    # The company is required for the Terms of Service and ignored for the Terms
    # of Use, which bind the person wherever they work.
    def record!(document, user:, company: nil, request: nil)
      create!(
        document: document.key,
        version: document.version,
        user: user,
        company: (company if document.accepted_by == :company),
        accepted_at: Time.current,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent.to_s.truncate(500).presence
      )
    end
  end
end
