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
    def issue(name:, email:, max_sessions:)
      verifier.generate(
        { "name" => name, "email" => email, "max_sessions" => max_sessions },
        expires_in: TTL
      )
    end

    # nil for a link that was tampered with, truncated, signed by another
    # installation, or has simply expired.
    def decode(token)
      payload = verifier.verified(token.to_s)
      return nil unless payload.is_a?(Hash)

      payload.symbolize_keys.slice(:name, :email, :max_sessions)
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
