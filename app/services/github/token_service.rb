# frozen_string_literal: true

module Github
  # The one place that turns a GitHub integration into a credential Octokit and
  # `git` can use. Two credential shapes live behind the same two methods:
  #
  #   app — a GitHub App installation. A JWT signed with the deployment's
  #         private key is exchanged for a short-lived installation token,
  #         optionally scoped to named repositories. The production path.
  #   pat — a user's personal access token, pasted in the connect dialog and
  #         stored encrypted. Nothing is minted: the stored token IS the
  #         credential, so `repositories:` cannot narrow it and the App
  #         installation-token refresh path must never be walked with it.
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    # Either one lets the token read repositories; `repo` additionally covers
    # private ones. Anything narrower cannot clone.
    REPO_SCOPES = %w[repo public_repo].freeze

    # An installation token lives an hour, and minting one per call spent a
    # GitHub request on every clone, listing and CI check. Kept in this process
    # only: a copy in Redis or the database would outlive every request that
    # needed it.
    TOKENS = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)
    TOKEN_MARGIN = 5.minutes

    def initialize(integration)
      @integration = integration
      validate_configuration!
    end

    def pat_mode?
      integration.github_pat?
    end

    # The credential for cloning, fetching and pushing.
    #
    # @param repositories [Array<String>] repo names to restrict access to (e.g. ["my-repo"])
    #   When empty, the token has access to all repos in the installation.
    #   IGNORED in PAT mode — a personal access token carries its owner's whole
    #   account and cannot be narrowed per call. Callers pass it for the App
    #   case and do not have to branch.
    def generate_installation_token(repositories: [])
      return personal_access_token if pat_mode?

      key = "#{installation_id}:#{repositories.map(&:to_s).sort.join(',')}"
      TOKENS.read(key) || mint_installation_token(key, repositories)
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

    # PAT counterpart of #verify_installation: who the token acts as, and what
    # it may do. `GET /user` is the cheapest call that answers both — the
    # `X-OAuth-Scopes` response header comes back on the same request.
    #
    # A fine-grained token sends no such header. Its permissions are per
    # repository and not enumerable from here, so it is accepted on the
    # strength of the call having succeeded at all; a classic token that
    # carries neither `repo` nor `public_repo` is refused, because it can read
    # no repository and would only fail later, at clone time, with nothing
    # pointing back at the token.
    def verify_token
      client = Octokit::Client.new(access_token: personal_access_token)
      user = client.user
      scopes = parse_scopes(client.last_response&.headers)

      if scopes && (scopes & REPO_SCOPES).empty?
        raise AuthenticationError,
              "This token has no repository access. A classic token needs the `repo` scope " \
              "(or `public_repo` for public repositories only); it currently has " \
              "#{scopes.presence&.join(', ') || 'no scopes'}."
      end

      { id: user.id, account_login: user.login, account_type: user.type, scopes: scopes }
    rescue Octokit::Unauthorized
      raise AuthenticationError, "GitHub rejected this token — it is invalid, revoked or expired."
    rescue Octokit::Error => e
      raise AuthenticationError, "GitHub token verification failed: #{e.message}"
    end

    private

    def mint_installation_token(key, repositories)
      client = Octokit::Client.new(bearer_token: generate_jwt)
      options = repositories.present? ? { repositories: repositories } : {}
      token = client.create_app_installation_access_token(installation_id, options)
      expires_at = token.expires_at.presence && (Time.zone.parse(token.expires_at.to_s) - TOKEN_MARGIN)
      TOKENS.write(key, token.token, expires_at: expires_at) if expires_at&.future?
      token.token
    rescue Octokit::Error => e
      raise AuthenticationError, "Failed to generate installation token: #{e.message}"
    end

    attr_reader :integration

    def installation_id
      @installation_id ||= integration.installation_id.to_i
    end

    def personal_access_token
      integration.github_personal_access_token.presence ||
        raise(ConfigurationError, "GitHub personal access token not configured")
    end

    # nil when GitHub sent no `X-OAuth-Scopes` header at all — a fine-grained
    # token, whose permissions this endpoint does not report. Distinct from an
    # empty list, which is a classic token that really carries no scope.
    def parse_scopes(headers)
      raw = headers && (headers["x-oauth-scopes"] || headers[:x_oauth_scopes])
      return nil if raw.nil?

      raw.to_s.split(",").map(&:strip).reject(&:blank?).sort
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
      raise ConfigurationError, "GitHub App private key not configured (set GITHUB_APP_PRIVATE_KEY or GITHUB_APP_PRIVATE_KEY_PATH)" if key_path.blank?
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

    # A PAT connection needs neither the deployment's App nor an installation —
    # requiring them is exactly what shut this path out of a local deployment.
    def validate_configuration!
      if integration.github_pat?
        raise ConfigurationError, "Integration has no personal access token" if integration.github_personal_access_token.blank?
        return
      end

      raise ConfigurationError, "GitHub App ID not configured" if Settings.github.app_id.blank?
      raise ConfigurationError, "Integration has no installation_id" if integration.installation_id.blank?
    end
  end
end
