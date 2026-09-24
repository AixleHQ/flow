# frozen_string_literal: true

module Github
  class IntegrationService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    # `via_setup:` — the id arrived on GitHub's own post-install redirect, with
    # our signed state. Only that path may connect an installation the company
    # does not hold yet (and, where the App's OAuth credentials are configured,
    # only for an installation the person completing the install can see).
    # Everywhere else — "link to project" — the id has to be one the company
    # already holds; the App's JWT can read every installation, so its existence
    # proves nothing about who installed it.
    def create(installation_id:, via_setup: false, oauth_code: nil)
      unless via_setup || Integration.github_installation_held_by?(@company, installation_id)
        return refused("This GitHub installation is not connected to this workspace")
      end
      if via_setup && Github::InstallationOwnership.enforced? &&
         !Github::InstallationOwnership.new(code: oauth_code).includes?(installation_id)
        return refused("Could not confirm you have access to this GitHub installation")
      end

      integration = Integration.find_or_build_github_for_installation(
        company: @company, connected_by: @connected_by, project: @project, installation_id: installation_id
      )
      integration.status = :inactive
      integration.credentials_data = { installation_id: installation_id.to_s }

      begin
        info = Github::TokenService.new(integration).verify_installation
        integration.name = info[:account_login]
        integration.settings = {
          auth_mode: "app",
          # Kept separately from `name`, which is a display label: Repository
          # checks the owner of every attached repo against this login, because
          # a clone token is scoped by repo NAME within this account.
          account_login: info[:account_login],
          account_type: info[:account_type],
          target_type: info[:target_type]
        }
        integration.status = :active
      rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
        integration.name = "GitHub (unverified)" if integration.name.blank?
        integration.status = :error
        integration.settings = { auth_mode: "app", error: e.message }
      end

      integration.save
      integration
    end

    # The developer path: a personal access token instead of an App
    # installation, for a deployment where no GitHub App exists or nobody can
    # install one.
    #
    # Unlike the App path, a token that does not verify is NOT persisted. An
    # unverified installation is worth keeping — the row holds the
    # installation id and repairs when the deployment's App config is fixed —
    # but an unverified token repairs by being pasted again, so a saved row
    # would only be litter with a dead secret in it. The caller reads
    # `settings["error"]` off the unsaved record to show why.
    def create_with_pat(personal_access_token:)
      integration = Integration.find_or_build_github_for_pat(
        company: @company,
        connected_by: @connected_by,
        project: @project
      )
      previous_credentials = integration.persisted? ? integration.credentials : nil
      integration.credentials_data = { personal_access_token: personal_access_token.to_s }
      # Before the token service is built, not after: `auth_mode` is what tells
      # it which credential shape this is, and without it a fresh record is
      # taken for an App installation and refused for having no installation id.
      integration.settings = integration.settings.to_h.merge("auth_mode" => "pat")

      begin
        info = Github::TokenService.new(integration).verify_token
      rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
        # A failed re-connect must not take the working connection down with
        # it: put the token that was there back and save nothing, so the
        # persisted row keeps the credential and the status it had.
        #
        # The record handed back is marked failed IN MEMORY only. That is what
        # the caller reports on — a re-connect that was rejected must not read
        # back as "connected" just because the row it targeted is still active
        # from last time.
        integration.credentials = previous_credentials
        integration.name = "GitHub (unverified)" if integration.name.blank?
        integration.status = :error
        integration.settings = integration.settings.to_h.merge("error" => e.message)
        return integration
      end

      integration.name = info[:account_login]
      integration.settings = {
        auth_mode: "pat",
        account_login: info[:account_login],
        account_type: info[:account_type],
        # Non-secret, and the one thing a "why can't it see my repo" answer
        # needs. nil for a fine-grained token, whose permissions GitHub does
        # not report on this endpoint.
        token_scopes: info[:scopes]
      }.compact
      integration.status = :active
      integration.save
      integration
    end

    private

    def refused(message)
      @company.integrations.build(
        provider: :github, connected_by: @connected_by, project: @project, status: :error,
        name: "GitHub (refused)", settings: { auth_mode: "app", error: message }
      )
    end
  end
end
