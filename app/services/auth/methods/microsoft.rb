# frozen_string_literal: true

module Auth
  module Methods
    # Microsoft work/school accounts via Entra ID.
    #
    # "Sign in with Teams" is this: Teams is a client surface that federates to
    # Entra, and the flow is an ordinary OIDC authorization code exchange.
    class Microsoft < Auth::Method
      # Entra's own tenant for personal Microsoft accounts (outlook.com,
      # hotmail.com …). A personal account's address is self-asserted, so it is
      # never allowed to promote an assertion onto an existing user (AD-3).
      PERSONAL_ACCOUNTS_TENANT = "9188040d-6c67-4c5b-b112-36a304b66dad"

      def complete(auth_hash:)
        raw = auth_hash&.[]("extra")&.[]("raw_info") || {}
        info = auth_hash&.[]("info") || {}

        # The immutable per-user object id, never the email or the UPN: a UPN is
        # renameable and an email is reassignable, and either would move an
        # account to a different person (AD-3).
        subject = raw["oid"].presence || auth_hash&.[]("uid")
        raise Auth::Method::Failure, "entra assertion carried no oid" if subject.blank?

        tenant = raw["tid"].to_s
        verify_tenant!(tenant)

        Auth::Assertion.new(
          provider: provider,
          subject: subject.to_s,
          email: info["email"].presence || raw["email"].presence || raw["preferred_username"],
          # Entra sends NO `email_verified` claim, and — unlike Google Workspace —
          # a tenant admin can set an arbitrary `mail`/`preferred_username` without
          # proving they own that address's domain, on a tenant anyone can create
          # for free. So this is never evidence the person controls the address,
          # and a Microsoft sign-in can create an account but never attach itself
          # to one that already exists (AD-3).
          email_verified: false,
          name: info["name"].presence || raw["name"]
        )
      end

      private

      # AD-13: a multi-tenant app registration will happily complete a sign-in
      # for ANY Entra directory, so an assertion must be checked against the row
      # it claims to satisfy. A company-scoped connection pins one tenant; a
      # deployment-scoped one accepts any, because the operator configured it.
      def verify_tenant!(tenant)
        expected = provider.config["tenant_id"].to_s
        return if provider.deployment? && expected.blank?
        return if expected.present? && expected == tenant

        raise Auth::Method::Failure,
              "entra assertion for tenant #{tenant.inspect} does not match this connection"
      end
    end
  end
end
