# frozen_string_literal: true

module Auth
  # Provider row -> adapter (AD-2). The one place a kind string is turned into
  # behaviour; nothing outside Auth:: constructs an adapter directly.
  module Registry
    ADAPTERS = {
      "password" => Auth::Methods::Password,
      "google" => Auth::Methods::Google,
      "microsoft" => Auth::Methods::Microsoft,
      "oidc" => Auth::Methods::Oidc,
      "magic_link" => Auth::Methods::MagicLink,
      "passkey" => Auth::Methods::Passkey,
      "totp" => Auth::Methods::Totp,
      "saml" => Auth::Methods::Saml
    }.freeze

    # The OmniAuth strategy name in /auth/:provider/callback is OmniAuth's
    # vocabulary, not ours: the same provider is "google" in our initializer and
    # "google_oauth2" upstream. Map it explicitly rather than treating a URL
    # segment as a provider kind.
    OMNIAUTH_STRATEGY_KINDS = {
      "google" => "google",
      "google_oauth2" => "google",
      "microsoft" => "microsoft",
      "entra_id" => "microsoft"
    }.freeze

    class UnsupportedKind < StandardError; end

    def self.for(provider)
      adapter = ADAPTERS[provider.kind.to_s]
      raise UnsupportedKind, "no adapter for provider kind #{provider.kind.inspect}" if adapter.nil?

      adapter.new(provider)
    end

    def self.supported_kinds
      ADAPTERS.keys
    end

    # @raise [UnsupportedKind] when the callback names a strategy we do not run
    def self.provider_for_omniauth(strategy_name)
      kind = OMNIAUTH_STRATEGY_KINDS[strategy_name.to_s]
      raise UnsupportedKind, "no provider for omniauth strategy #{strategy_name.inspect}" if kind.nil?

      IdentityProvider.deployment!(kind)
    end
  end
end
