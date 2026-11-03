# frozen_string_literal: true

# The emailed half of signing a company up.
#
# A stranger filling the form has proved nothing: the address they typed may be
# anyone's. So nothing is written — the answers travel in a link to that
# address, and receiving it is what proves the person controls the mailbox they
# claimed. Until the link is opened, the signup exists only in an inbox.
#
# Deliberately not a table. There is nothing to reserve before the address is
# proved (a row keyed by domain would be a squat), and nothing to clean up when
# a link is never opened.
#
# Encrypted, not only signed: an acceptance of the terms carries the IP address
# and browser it was given from, and those have no business being readable in
# a mailbox or a mail log.
class WorkspaceSignupTicket
  PURPOSE = "workspace_signup"

  # Long enough to survive a mail queue, a night, and a person who reads it the
  # next morning. Not single-use: the writes it authorises collide on the
  # company's unique domain, so a second click cannot make a second workspace.
  TTL = 24.hours

  class << self
    # `acceptance` is the LegalAcceptance::Evidence of a ticked box, nil for none.
    def issue(name:, email:, marketplace_license_id: nil, acceptance: nil)
      answers = { "name" => name, "email" => email }
      if acceptance
        # The versions the box was ticked for: a link opened after they changed
        # carries no acceptance, and the form asks again.
        answers["accepted_terms"] = LegalDocument.fingerprint
        answers["acceptance"] = {
          "at" => acceptance.accepted_at.iso8601(6), "ip" => acceptance.ip_address, "user_agent" => acceptance.user_agent
        }
      end
      # Only when there is one, so an ordinary signup's ticket keeps the shape it
      # had. The link may be opened in another browser, where the session that
      # held the licence does not exist.
      answers["marketplace_license_id"] = marketplace_license_id if marketplace_license_id

      encryptor.encrypt_and_sign(answers, expires_in: TTL, purpose: PURPOSE)
    end

    # nil for a link that was tampered with, truncated, made by another
    # installation, or has simply expired.
    def decode(token)
      payload = read(token.to_s)
      return nil unless payload.is_a?(Hash)

      answers = payload.symbolize_keys
      acceptance = (evidence(answers[:acceptance]) if answers[:accepted_terms] == LegalDocument.fingerprint)
      answers.slice(:name, :email, :marketplace_license_id).merge(accept_terms: acceptance.present?, acceptance: acceptance)
    end

    private

    # Links sent before tickets were encrypted are only signed, and carry no
    # acceptance. Read until they expire, so a link already in an inbox across
    # the deploy still works; remove once a release with encryption has shipped.
    def read(token)
      encryptor.decrypt_and_verify(token, purpose: PURPOSE)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      Rails.application.message_verifier(PURPOSE).verified(token)
    end

    def evidence(given)
      return nil unless given.is_a?(Hash) && given["at"].present?

      LegalAcceptance::Evidence.new(
        accepted_at: Time.iso8601(given["at"]), ip_address: given["ip"], user_agent: given["user_agent"]
      )
    rescue ArgumentError
      nil
    end

    def encryptor
      ActiveSupport::MessageEncryptor.new(
        Rails.application.key_generator.generate_key("#{PURPOSE} ticket encryption", 32), url_safe: true
      )
    end
  end
end
