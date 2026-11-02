# frozen_string_literal: true

# The emailed half of signing a company up.
#
# A stranger filling the form has proved nothing: the address they typed may be
# anyone's. So nothing is written — the answers travel in a signed link to that
# address, and receiving it is what proves the person controls the mailbox they
# claimed. Until the link is opened, the signup exists only in an inbox.
#
# Deliberately not a table. There is nothing to reserve before the address is
# proved (a row keyed by domain would be a squat), and nothing to clean up when
# a link is never opened.
class WorkspaceSignupTicket
  PURPOSE = "workspace_signup"

  # Long enough to survive a mail queue, a night, and a person who reads it the
  # next morning. Not single-use: the writes it authorises collide on the
  # company's unique domain, so a second click cannot make a second workspace.
  TTL = 24.hours

  class << self
    def issue(name:, email:, marketplace_license_id: nil, accept_terms: false)
      answers = { "name" => name, "email" => email }
      # The versions the box was ticked for: a link opened after they changed
      # carries no acceptance, and the form asks again.
      answers["accepted_terms"] = LegalDocument.fingerprint if accept_terms
      # Only when there is one, so an ordinary signup's ticket keeps the shape it
      # had. The link may be opened in another browser, where the session that
      # held the licence does not exist.
      answers["marketplace_license_id"] = marketplace_license_id if marketplace_license_id

      verifier.generate(answers, expires_in: TTL)
    end

    # nil for a link that was tampered with, truncated, signed by another
    # installation, or has simply expired.
    def decode(token)
      payload = verifier.verified(token.to_s)
      return nil unless payload.is_a?(Hash)

      answers = payload.symbolize_keys
      answers.slice(:name, :email, :marketplace_license_id)
             .merge(accept_terms: answers[:accepted_terms].present? && answers[:accepted_terms] == LegalDocument.fingerprint)
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
