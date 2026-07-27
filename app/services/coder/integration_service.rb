# frozen_string_literal: true

module Coder
  # Connects (or reconnects) a Coder integration for a (company, project) pair.
  #
  # Persists the integration in either `:active` state (token verified) or
  # `:error` state (verification failed) — the record is saved either way so
  # the user can repair from the integrations page. Mirrors the GitLab pattern.
  class IntegrationService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end
    class InvalidUrlError < StandardError; end

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(coder_url:, session_token:, default_template: nil, machine_prefix: nil, lock_ttl_minutes: nil)
      normalized_url = normalize_url(coder_url)
      integration = build_integration

      url_errors = UrlSafetyValidator.errors_for(
        normalized_url
      )
      if url_errors.any?
        integration.credentials_data = {
          coder_url: normalized_url,
          session_token: session_token.to_s
        }
        integration.name = "Coder (unverified)"
        integration.status = :error
        integration.settings = { error: "Coder URL #{url_errors.first}" }
        integration.save
        return integration
      end

      ttl_value = parse_positive_int(lock_ttl_minutes)
      if ttl_value.nil?
        integration.credentials_data = {
          coder_url: normalized_url,
          session_token: session_token.to_s
        }
        integration.name = "Coder (unverified)"
        integration.status = :error
        integration.settings = { error: "Lock TTL minutes is required" }
        integration.save
        return integration
      end

      integration.credentials_data = {
        coder_url: normalized_url,
        session_token: session_token.to_s
      }

      begin
        info = Coder::TokenService.new(integration).verify_token
        integration.name = display_name_for(info[:username])
        integration.credentials_data = integration.credentials_data.merge(user_id: info[:id])
        integration.settings = {
          coder_username:    info[:username],
          coder_user_email:  info[:email],
          default_template:  default_template.presence,
          machine_prefix:    machine_prefix.presence,
          lock_ttl_minutes:  ttl_value
        }.compact
        integration.status = :active
      rescue Coder::TokenService::ConfigurationError,
             Coder::TokenService::AuthenticationError => e
        integration.name = "Coder (unverified)" if integration.name.blank?
        integration.status = :error
        integration.settings = { error: e.message }
      end

      integration.save
      integration
    end

    private

    def build_integration
      @company.integrations.build(
        provider: :coder,
        connected_by: @connected_by,
        project: @project
      )
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
