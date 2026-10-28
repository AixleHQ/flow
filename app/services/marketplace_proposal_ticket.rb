# frozen_string_literal: true

# The emailed half of asking for a subscription to be applied to a workspace
# that already exists.
#
# The buyer has typed an address, which proves nothing — and a proposal raised
# on a typed address is a way to put a request in front of the administrators of
# any domain, from any AWS account. So nothing is raised until a link sent to
# that address is opened, exactly as WorkspaceSignupTicket proves an address
# before a workspace is created.
#
# Deliberately not a table, for the same reason: there is nothing to reserve
# before the address is proved, and nothing to clean up when a link is never
# opened.
class MarketplaceProposalTicket
  PURPOSE = "marketplace_license_proposal"

  # Shorter than a signup's day. The buyer is mid-purchase with the page in
  # front of them, and the link authorises putting a request in front of
  # somebody else.
  TTL = 2.hours

  class << self
    # Dated, because two links for the same licence and address are otherwise
    # the same link: one issued before the administrators answered is a reload
    # of the request they declined, one issued after is a new ask.
    def issue(license_id:, email:)
      verifier.generate({ "license_id" => license_id, "email" => email, "issued_at" => Time.current.to_i },
                        expires_in: TTL)
    end

    # nil for a link that was tampered with, signed by another installation, or
    # has simply expired. `issued_at` is nil on a link from before it was dated.
    def decode(token)
      payload = verifier.verified(token.to_s)
      return nil unless payload.is_a?(Hash)

      answers = payload.symbolize_keys.slice(:license_id, :email, :issued_at)
      answers[:issued_at] = answers[:issued_at] && Time.zone.at(answers[:issued_at].to_i)
      answers
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
