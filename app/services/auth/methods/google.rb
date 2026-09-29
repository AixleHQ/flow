# frozen_string_literal: true

module Auth
  module Methods
    # Google via OmniAuth. Deployment-scoped: one OAuth client for the whole
    # installation, so the company is discovered from the email domain after the
    # assertion completes, not before it starts.
    class Google < Auth::Method
      def complete(auth_hash:)
        info = auth_hash&.[]("info") || {}
        uid = auth_hash&.[]("uid")
        raise Auth::Method::Failure, "google assertion carried no uid" if uid.blank?

        Auth::Assertion.new(
          provider: provider,
          subject: uid.to_s,
          email: info["email"],
          email_verified: verified?(auth_hash, info),
          name: info["name"],
          avatar_url: info["image"]
        )
      end

      private

      # omniauth-google-oauth2 surfaces the claim in `extra.raw_info` (straight
      # from the id_token) and, depending on version, mirrors it into `info`.
      # Read both, and treat ABSENT as false — an absent claim is not a true
      # claim (AD-3).
      def verified?(auth_hash, info)
        raw = auth_hash["extra"]&.[]("raw_info") || {}
        truthy?(info["email_verified"]) || truthy?(raw["email_verified"])
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end
    end
  end
end
