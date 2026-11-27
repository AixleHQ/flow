# frozen_string_literal: true

module Coder
  # Connects a project to a Coder deployment, replaces the session token, and
  # re-checks it (docs/design/session-integrations.md §4.1, §4.2).
  #
  # A scope may hold several Coder integrations, with no identity rules: what a
  # user connects is the user's business, and `create` always makes a new one.
  # Which one a session uses is decided by the integrations attached to it. A
  # token Coder refuses, or cannot be asked about, is never saved. A default
  # template and a machine prefix are required (#294).
  class IntegrationService
    class ConfigurationError < StandardError; end

    # `code`: "validation_failed", "not_authorized" (Coder refused the token),
    # or "unreachable" (Coder could not be asked).
    class ConnectionError < StandardError
      attr_reader :code

      def initialize(message, code:)
        super(message)
        @code = code
      end
    end

    REJECTED = "Coder no longer accepts this connection's session token. Replace the token."

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(coder_url:, session_token:, default_template: nil, machine_prefix: nil, lock_ttl_minutes: nil)
      url = normalize_url(coder_url)
      token = session_token.to_s.strip
      ttl = parse_positive_int(lock_ttl_minutes) ||
            raise(ConnectionError.new("Lock TTL minutes is required", code: "validation_failed"))
      require_pool_settings!(default_template, machine_prefix)
      info = verify!(url, token)
      require_known_template!(default_template, template_names(url, token))

      integration = build_integration
      apply(integration, url, token, info)
      integration.settings = integration.settings.merge(
        "default_template" => default_template.to_s.strip, "machine_prefix" => machine_prefix.to_s.strip,
        "lock_ttl_minutes" => ttl
      )
      integration.save!
      integration
    end

    # The templates a token can see, for the connect form's select. The token is not saved
    # yet, so the form sends the URL and the token it just collected.
    def templates(coder_url:, session_token:)
      url = normalize_url(coder_url)
      token = session_token.to_s.strip
      check_connection_input!(url, token)
      template_names(url, token)
    end

    # Renew token: the new token has to work against the integration's own URL. The
    # integration keeps its id, which runners and attachments refer to.
    def replace_token(integration, session_token:)
      raise ConfigurationError, "Only Coder integrations have a session token" unless integration.coder?

      token = session_token.to_s.strip
      info = verify!(integration.coder_url.to_s, token)
      apply(integration, integration.coder_url, token, info)
      integration.save!
      integration
    end

    # Re-checks the stored token. Only Coder refusing it marks the connection
    # for attention; Coder being unreachable says nothing about the token.
    def test(integration)
      info = Coder::TokenService.new(integration).verify_token
      integration.update!(name: display_name_for(info[:username]), status: :active,
                          settings: identity(integration, info).merge("last_verified_at" => Time.current.iso8601))
      { status: :active }
    rescue Coder::TokenService::AuthenticationError => e
      return { status: :error, error: "unreachable", message: e.message } unless e.rejected?

      mark_rejected(integration)
      { status: :error, error: "not_authorized", message: REJECTED }
    rescue Coder::TokenService::ConfigurationError
      mark_rejected(integration)
      { status: :error, error: "not_authorized", message: REJECTED }
    rescue ConnectionError => e
      { status: :error, error: e.code, message: e.message }
    end

    # Edit the operational settings of a connected integration in place. Only
    # these three are editable: they change how the allocator behaves and carry no
    # secret. The template and the prefix are required, also on a row that was
    # connected before they were, and the template has to be one the stored token
    # can see. A blank or non-positive `lock_ttl_minutes` is rejected, since the
    # lock TTL has no sane "unset" (the allocator would silently fall back to its
    # own default).
    def update_settings(integration:, default_template: nil, machine_prefix: nil, lock_ttl_minutes: nil)
      raise ConfigurationError, "Only Coder integrations have editable settings" unless integration.coder?

      ttl_value = parse_positive_int(lock_ttl_minutes)
      raise ConfigurationError, "Lock TTL minutes must be a positive number" if ttl_value.nil?

      require_pool_settings!(default_template, machine_prefix)
      stored = Coder::TokenService.new(integration)
      require_known_template!(default_template, template_names(stored.coder_url, stored.session_token))

      integration.update!(
        settings: (integration.settings || {}).merge(
          "default_template" => default_template.to_s.strip,
          "machine_prefix"   => machine_prefix.to_s.strip,
          "lock_ttl_minutes" => ttl_value
        )
      )
      integration
    rescue Coder::TokenService::ConfigurationError
      raise ConnectionError.new("The stored session token cannot be read. Renew the token first.", code: "not_authorized")
    end

    private

    def build_integration
      @company.integrations.build(provider: :coder, project: @project)
    end

    def verify!(url, token)
      check_connection_input!(url, token)

      candidate = Integration.new(provider: :coder, company: @company)
      candidate.credentials_data = { "coder_url" => url, "session_token" => token }
      Coder::TokenService.new(candidate).verify_token
    rescue Coder::TokenService::AuthenticationError => e
      raise ConnectionError.new(e.message, code: e.rejected? ? "not_authorized" : "unreachable")
    end

    def check_connection_input!(url, token)
      url_errors = UrlSafetyValidator.errors_for(url, trusted_hosts_override: UrlSafetyValidator.configured_trusted_hosts)
      raise ConnectionError.new("Coder URL #{url_errors.first}", code: "validation_failed") if url_errors.any?
      raise ConnectionError.new("Enter a Coder session token", code: "validation_failed") if token.blank?
    end

    # The names of the templates this token can see, sorted. Coder's refusal and Coder being
    # out of reach are told apart, as `verify!` does.
    def template_names(url, token)
      Coder::Api.list_templates(coder_url: url, session_token: token).filter_map { |t| t["name"].presence }.sort
    rescue Coder::Api::HTTPError => e
      raise ConnectionError.new("Coder did not list its templates (HTTP #{e.status})",
                                code: [ 401, 403 ].include?(e.status) ? "not_authorized" : "unreachable")
    rescue Coder::Api::ApiError
      raise ConnectionError.new("Coder could not be reached to list its templates", code: "unreachable")
    end

    # Both are required on connect and on every settings save (#294).
    def require_pool_settings!(default_template, machine_prefix)
      if default_template.to_s.strip.empty?
        raise ConnectionError.new("Default template is required", code: "validation_failed")
      end
      return if Coder::Pool.valid_prefix?(machine_prefix.to_s.strip)

      raise ConnectionError.new(
        "Machine prefix is required: lowercase letters, digits and hyphens, no leading or trailing hyphen, " \
        "at most #{Coder::Pool::MAX_PREFIX_LENGTH} characters", code: "validation_failed"
      )
    end

    def require_known_template!(default_template, names)
      return if names.include?(default_template.to_s.strip)

      raise ConnectionError.new("Default template #{default_template.to_s.strip.inspect} is not one of the templates " \
                                "this token can see", code: "validation_failed")
    end

    def apply(integration, url, token, info)
      integration.credentials_data = { "coder_url" => url, "session_token" => token, "user_id" => info[:id] }
      integration.assign_attributes(name: display_name_for(info[:username]), status: :active,
                                    connected_by: @connected_by, settings: identity(integration, info))
    end

    def identity(integration, info)
      integration.settings.to_h.except("error").merge(
        { "coder_username" => info[:username], "coder_user_email" => info[:email] }.compact
      )
    end

    def mark_rejected(integration)
      integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => REJECTED),
                                 updated_at: Time.current)
    end

    def normalize_url(url)
      url.to_s.strip.chomp("/")
    end

    # Per requester ask on PR #257: distinguish the integration with a "Coder"
    # prefix so the per-user identity is recognisable in lists that mix
    # multiple integration providers.
    def display_name_for(username)
      username = username.to_s.strip
      username.empty? ? "Coder" : "Coder (#{username})"
    end

    def parse_positive_int(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Integer(value.to_s, 10).then { |i| i.positive? ? i : nil }
    rescue ArgumentError, TypeError
      nil
    end
  end
end
