# frozen_string_literal: true

module Github
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(integration)
      @integration = integration
      validate_configuration!
    end

    def generate_installation_token
      jwt = generate_jwt
      client = Octokit::Client.new(bearer_token: jwt)
      token = client.create_app_installation_access_token(installation_id)
      token.token
    rescue Octokit::Error => e
      raise AuthenticationError, "Failed to generate installation token: #{e.message}"
    end

    def verify_installation
      jwt = generate_jwt
      client = Octokit::Client.new(bearer_token: jwt)
      installation = client.installation(installation_id)

      {
        id: installation.id,
        account_login: installation.account.login,
        account_type: installation.account.type,
        target_type: installation.target_type,
        permissions: installation.permissions.to_h
      }
    rescue Octokit::Error => e
      raise AuthenticationError, "Failed to verify installation: #{e.message}"
    end

    private

    attr_reader :integration

    def installation_id
      @installation_id ||= integration.installation_id.to_i
    end

    def generate_jwt
      payload = {
        iat: Time.now.to_i - 60,
        exp: 10.minutes.from_now.to_i,
        iss: app_id
      }
      JWT.encode(payload, private_key, "RS256")
    end

    def app_id
      Settings.github.app_id.to_s
    end

    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(read_private_key)
    end

    def read_private_key
      key_content = Settings.github.private_key
      return normalize_pem(key_content) if key_content.present?

      key_path = Settings.github.private_key_path
      raise ConfigurationError, "GitHub App private key not configured (set GITHUB_APP_PRIVATE_KEY or GITHUB_PRIVATE_KEY_PATH)" if key_path.blank?
      raise ConfigurationError, "GitHub App private key file not found at #{key_path}" unless File.exist?(key_path)

      File.read(key_path)
    end

    def normalize_pem(raw)
      pem = raw.gsub('\n', "\n")
      return pem if pem.count("\n") > 2

      match = pem.match(/(-----BEGIN [A-Z ]+-----)\s*(.+?)\s*(-----END [A-Z ]+-----)/)
      raise ConfigurationError, "Invalid PEM format" unless match

      header, body, footer = match[1], match[2], match[3]
      base64 = body.gsub(/\s+/, "").scan(/.{1,64}/).join("\n")
      "#{header}\n#{base64}\n#{footer}\n"
    end

    def validate_configuration!
      raise ConfigurationError, "GitHub App ID not configured" if Settings.github.app_id.blank?
      raise ConfigurationError, "Integration has no installation_id" if integration.installation_id.blank?
    end
  end
end
