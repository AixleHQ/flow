# frozen_string_literal: true

module Auth
  module Methods
    # A single-use emailed sign-in link.
    #
    # The subject is the user's own id, exactly as for a password: this is a
    # local credential proving control of the mailbox, not a federated identity.
    class MagicLink < Auth::Method
      def complete(token:)
        user = MagicLinkToken.consume(token)
        return nil if user.nil?

        Auth::Assertion.new(
          provider: provider,
          subject: user.id.to_s,
          email: user.email,
          # Redeeming a link sent to that address IS the proof of control.
          email_verified: true,
          name: user.name
        )
      end
    end
  end
end
