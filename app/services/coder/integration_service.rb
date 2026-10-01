# frozen_string_literal: true

module Coder
  # Connects a project to a Coder deployment, replaces the session token, and
  # re-checks it.
  #
  # A scope holds at most one active Coder connection: the coder_* tools pick
  # one per project, and with two the pick is arbitrary. Connecting the same
  # URL as the same account again renews that row. A token Coder refuses, or
  # cannot be asked about, is never saved.
  class IntegrationService
    class ConfigurationError < StandardError; end

    # `code`: "validation_failed", "not_authorized" (Coder refused the token),
    # "unreachable" (Coder could not be asked), or "already_connected".
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

    # Pool settings left blank keep what a renewed row already has: clearing
    # them is a deliberate edit (#update_settings), and a blank prefix widens
    # the pool to every workspace the token can see.
    def create(coder_url:, session_token:, default_template: nil, machine_prefix: nil, lock_ttl_minutes: nil)
      url = normalize_url(coder_url)
      token = session_token.to_s.strip
      ttl = parse_positive_int(lock_ttl_minutes) ||
            raise(ConnectionError.new("Lock TTL minutes is required", code: "validation_failed"))
      info = verify!(url, token)

      integration = existing_for(url, info) || build_integration
      ensure_only_active!(integration)
      apply(integration, url, token, info)
      integration.settings = integration.settings.merge(
        { "default_template" => default_template.presence, "machine_prefix" => machine_prefix.presence }.compact
      ).merge("lock_ttl_minutes" => ttl)
      integration.save!
      integration
    end

    def replace_token(integration, session_token:)
      raise ConfigurationError, "Only Coder integrations have a session token" unless integration.coder?

      token = session_token.to_s.strip
      info = verify!(integration.coder_url.to_s, token)
      if existing_for(integration.coder_url, info, except: integration)
        raise ConnectionError.new("#{display_name_for(info[:username])} already has another connection here. " \
                                  "Replace the token on that one.", code: "already_connected")
      end

      ensure_only_active!(integration)
      apply(integration, integration.coder_url, token, info)
      integration.save!
      integration
    end

    # Re-checks the stored token. Only Coder refusing it marks the connection
    # for attention; Coder being unreachable says nothing about the token.
    def test(integration)
      info = Coder::TokenService.new(integration).verify_token
      ensure_only_active!(integration)
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
    # these three are editable: they change how the allocator behaves, carry no
    # secret, and need no round-trip to Coder to validate.
    #
    # A blank `default_template` or `machine_prefix` clears the setting; blank
    # or non-positive `lock_ttl_minutes` is rejected, since the lock TTL has no
    # sane "unset" (the allocator would silently fall back to its own default).
    def update_settings(integration:, default_template: nil, machine_prefix: nil, lock_ttl_minutes: nil)
      raise ConfigurationError, "Only Coder integrations have editable settings" unless integration.coder?

      ttl_value = parse_positive_int(lock_ttl_minutes)
      raise ConfigurationError, "Lock TTL minutes must be a positive number" if ttl_value.nil?

      integration.update!(
        settings: (integration.settings || {}).merge(
          "default_template" => default_template.presence,
          "machine_prefix"   => machine_prefix.presence,
          "lock_ttl_minutes" => ttl_value
        ).compact
      )
      integration
    end

    private

    def build_integration
      @company.integrations.build(provider: :coder, project: @project)
    end

    def scope
      @company.integrations.where(provider: :coder, project_id: @project&.id)
    end

    def verify!(url, token)
      url_errors = UrlSafetyValidator.errors_for(url, trusted_hosts_override: UrlSafetyValidator.configured_trusted_hosts)
      raise ConnectionError.new("Coder URL #{url_errors.first}", code: "validation_failed") if url_errors.any?
      raise ConnectionError.new("Enter a Coder session token", code: "validation_failed") if token.blank?

      candidate = Integration.new(provider: :coder, company: @company)
      candidate.credentials_data = { "coder_url" => url, "session_token" => token }
      Coder::TokenService.new(candidate).verify_token
    rescue Coder::TokenService::AuthenticationError => e
      raise ConnectionError.new(e.message, code: e.rejected? ? "not_authorized" : "unreachable")
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

    # The row this URL and account already have here. A row a failed attempt
    # saved holds the URL but never learned the account, and is taken over.
    def existing_for(url, info, except: nil)
      rows = scope.to_a.reject { |row| row == except }
      rows = rows.select { |row| row.credentials_data_for_display["coder_url"] == url }
      rows.find { |row| row.coder_user_id.present? && row.coder_user_id == info[:id] } ||
        (rows.find { |row| row.coder_user_id.blank? && !row.active? } unless except)
    end

    def ensure_only_active!(integration)
      return if integration.persisted? && integration.active?

      other = scope.where(status: "active").where.not(id: integration.id).first
      return unless other

      raise ConnectionError.new("#{other.name} is already connected here. Replace its token, " \
                                "or remove it before connecting another Coder account.", code: "already_connected")
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
