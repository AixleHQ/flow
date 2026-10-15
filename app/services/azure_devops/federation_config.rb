# frozen_string_literal: true

module AzureDevops
  # This deployment as an OIDC issuer for customer-owned Entra apps (workload
  # identity federation). The customer's federated credential pins the issuer
  # URL, so it is fixed for the life of every connection: changing the domain
  # breaks all of them at once.
  #
  # Like the rest of the integration there is no enable flag. Federation is
  # offered exactly when a signing key is configured and the issuer is a public
  # HTTPS origin Entra can fetch keys from.
  class FederationConfig
    AUDIENCE = "api://AzureADTokenExchange"
    MIN_KEY_BITS = 2048
    DISCOVERY_PATH = "/.well-known/openid-configuration"
    JWKS_PATH = "/.well-known/jwks.json"

    class << self
      def enabled?
        signing_key.present? && issuer_usable?
      end

      # No trailing slash: Entra compares the issuer as a string, and the same
      # URL spelled two ways is two different issuers.
      def issuer_url
        configured = settings&.issuer_url.presence || "#{Settings.protocol}://#{Settings.domain}"
        configured.to_s.strip.chomp("/")
      end

      def audience
        settings&.audience.presence || AUDIENCE
      end

      # Parsed once per distinct PEM: every call to a federated installation asks
      # whether the feature is on, and parsing a private key is not free.
      def signing_key
        pem = settings&.signing_key.presence.to_s
        return nil if pem.blank?
        return @parsed_key.last if @parsed_key&.first == pem

        @parsed_key = [ pem, parse_signing_key(pem) ].freeze
        @parsed_key.last
      end

      def signing_key!
        signing_key || raise(CredentialActionRequired,
                             "The Azure DevOps federation signing key is missing or is not an RSA private key " \
                             "of at least #{MIN_KEY_BITS} bits")
      end

      # Identifies a key by its RFC 7638 thumbprint, so rotating needs no
      # separate id to keep in step with the key.
      def key_id(key)
        public_jwk = { e: base64url(key.e.to_s(2)), kty: "RSA", n: base64url(key.n.to_s(2)) }
        base64url(OpenSSL::Digest::SHA256.digest(public_jwk.to_json))
      end

      def current_key_id = key_id(signing_key!)

      # The current key first, then the previous public keys an operator keeps
      # published while tokens signed with them may still be in flight. A key
      # in the set is published before it is switched to, never after.
      def jwks
        keys = [ signing_key!, *previous_public_keys ].map { |key| jwk(key) }.uniq { |entry| entry[:kid] }
        { keys: keys }
      end

      def discovery_document
        {
          issuer: issuer_url,
          jwks_uri: "#{issuer_url}#{JWKS_PATH}",
          response_types_supported: [ "id_token" ],
          subject_types_supported: [ "public" ],
          id_token_signing_alg_values_supported: [ "RS256" ]
        }
      end

      private

      def settings
        Settings.azure_devops&.federation
      end

      def parse_signing_key(pem)
        key = OpenSSL::PKey::RSA.new(pem)
        key.private? && key.n.num_bits >= MIN_KEY_BITS ? key : nil
      rescue OpenSSL::PKey::RSAError
        nil
      end

      # Entra fetches the keys itself, from the public internet, over HTTPS, at
      # `<issuer>/.well-known/...`. An http, loopback or private origin, or an
      # issuer with a path (this app serves the documents at the root only),
      # can never work, so it is not offered rather than failing at the first
      # customer.
      def issuer_usable?
        uri = URI.parse(issuer_url)
        uri.scheme == "https" && uri.path.blank? && uri.query.nil? && AppConfig.reachable_from_azure?(issuer_url)
      rescue URI::InvalidURIError
        false
      end

      def previous_public_keys
        Array(settings&.previous_public_keys).filter_map do |pem|
          key = OpenSSL::PKey::RSA.new(pem.to_s)
          key.public? ? OpenSSL::PKey::RSA.new(key.public_to_der) : nil
        rescue OpenSSL::PKey::RSAError
          nil
        end
      end

      def jwk(key)
        { kty: "RSA", use: "sig", alg: "RS256", kid: key_id(key),
          n: base64url(key.n.to_s(2)), e: base64url(key.e.to_s(2)) }
      end

      def base64url(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end
    end
  end
end
