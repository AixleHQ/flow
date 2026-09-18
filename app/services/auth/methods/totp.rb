# frozen_string_literal: true

module Auth
  module Methods
    # Time-based one-time codes, as a STEP-UP method only.
    #
    # TOTP never starts a session: a code proves possession of a device, not who
    # the person is, so there is nobody to look up from it. It appends a proof to
    # a session that already exists — which is how a company can require it
    # without the conjunctive proof semantics the spine defers.
    class Totp < Auth::Method
      DRIFT = 30 # seconds either side, for clock skew

      class NotAStartMethod < Auth::Method::Failure; end

      def complete(user:, code:)
        raise NotAStartMethod, "TOTP cannot start a session" if user.nil?
        return nil unless user.totp_enabled?
        return nil unless user.verify_totp(code, drift: DRIFT)

        Auth::Assertion.new(
          provider: provider,
          subject: user.id.to_s,
          email: user.email,
          email_verified: true,
          name: user.name
        )
      end
    end
  end
end
