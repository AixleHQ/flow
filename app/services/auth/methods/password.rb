# frozen_string_literal: true

module Auth
  module Methods
    # Local password. The subject is the user's own id — a local credential has
    # no external identifier, and the id is stable and unique per provider.
    class Password < Auth::Method
      def complete(email:, password:)
        user = User.active.not_deleted.find_by(email: email)

        # Timing equalisation: always run one bcrypt comparison, matching
        # UserSignInForm's existing dummy-digest behaviour.
        if user&.password_digest.blank?
          BCrypt::Password.create("dummy-timing-equalisation") if user.nil?
          return nil
        end

        return nil unless user.authenticate(password)

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
