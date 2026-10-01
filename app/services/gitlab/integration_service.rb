# frozen_string_literal: true

module Gitlab
  # Connects a project to GitLab with a personal access token, replaces that
  # token, and re-checks it.
  #
  # A connection is one GitLab account in one scope: connecting the same
  # account again renews that row, so its repositories stay attached. A token
  # GitLab refuses, or cannot be asked about, is never saved.
  class IntegrationService
    # `code`: "validation_failed" (nothing to check), "not_authorized" (GitLab
    # refused the token), "unreachable" (GitLab could not be asked), or
    # "already_connected".
    class ConnectionError < StandardError
      attr_reader :code

      def initialize(message, code:)
        super(message)
        @code = code
      end
    end

    UNVERIFIED_NAME = "GitLab (unverified)"
    REJECTED = "GitLab no longer accepts this connection's token. Replace the token."

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(personal_access_token:)
      token = personal_access_token.to_s.strip
      info = verify!(token)
      integration = existing_for(info) || @company.integrations.build(provider: :gitlab, project: @project)
      apply(integration, token, info)
      integration.save!
      integration
    end

    def replace_token(integration, personal_access_token:)
      token = personal_access_token.to_s.strip
      info = verify!(token)
      if existing_for(info, except: integration)
        raise ConnectionError.new("#{info[:username]} already has another GitLab connection here. " \
                                  "Replace the token on that one.", code: "already_connected")
      end

      apply(integration, token, info)
      integration.save!
      integration
    end

    # Re-checks the stored token. Only GitLab refusing it marks the connection
    # for attention; GitLab being unreachable says nothing about the token.
    def test(integration)
      info = Gitlab::TokenService.new(integration).verify_token
      integration.update!(name: info[:username], status: :active,
                          settings: identity(integration, info).merge("last_verified_at" => Time.current.iso8601))
      { status: :active }
    rescue Gitlab::TokenService::AuthenticationError, Gitlab::TokenService::ConfigurationError => e
      integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => REJECTED),
                                 updated_at: Time.current)
      { status: :error, error: "not_authorized", message: e.message }
    rescue Gitlab::TokenService::ConnectionError => e
      { status: :error, error: "unreachable", message: e.message }
    end

    private

    def verify!(token)
      raise ConnectionError.new("Enter a GitLab personal access token.", code: "validation_failed") if token.blank?

      candidate = Integration.new(provider: :gitlab, company: @company)
      candidate.credentials_data = { "personal_access_token" => token }
      Gitlab::TokenService.new(candidate).verify_token
    rescue Gitlab::TokenService::AuthenticationError => e
      raise ConnectionError.new(e.message, code: "not_authorized")
    rescue Gitlab::TokenService::ConnectionError => e
      raise ConnectionError.new(e.message, code: "unreachable")
    end

    def apply(integration, token, info)
      integration.credentials_data = { "personal_access_token" => token }
      integration.assign_attributes(name: info[:username], status: :active, connected_by: @connected_by,
                                    settings: identity(integration, info))
    end

    def identity(integration, info)
      integration.settings.to_h.except("error").merge("gitlab_user_id" => info[:id], "gitlab_username" => info[:username])
    end

    # The row this account already has in this scope. Rows made before the
    # account was recorded are matched by the username they were named after,
    # or, for a failed attempt that saved a row, by its placeholder name.
    def existing_for(info, except: nil)
      rows = @company.integrations.where(provider: :gitlab, project_id: @project&.id)
      rows = rows.where.not(id: except.id) if except
      unrecorded = rows.where("settings ->> 'gitlab_user_id' IS NULL")
      rows.find_by("settings ->> 'gitlab_user_id' = ?", info[:id].to_s) ||
        unrecorded.find_by(name: info[:username]) ||
        (unrecorded.find_by(name: UNVERIFIED_NAME, status: "error") unless except)
    end
  end
end
