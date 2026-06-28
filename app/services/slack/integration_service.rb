# frozen_string_literal: true

module Slack
  # Connects a Slack workspace to a (company, project) via OAuth v2. Aixle runs
  # ONE Slack app per deployment (app credentials in Settings.slack.*); each
  # company installs it into its own workspace with one click, yielding a
  # per-workspace bot token. The install is keyed by `team_id` (stored in
  # `settings` for inbound routing) and the bot token lives in encrypted
  # `credentials_data`. Persists :active on success or :error otherwise, so the
  # user can repair from the integrations page (mirrors GitLab/Coder).
  class IntegrationService
    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    # Exchange the OAuth code for a bot token and persist the install.
    def create_from_oauth(code:, redirect_uri: Slack::Oauth.redirect_uri)
      data = Slack::Client.exchange_code(code: code, redirect_uri: redirect_uri)
      team = data["team"].to_h
      team_id = team["id"].to_s
      return save_error(build_integration, "Slack did not return a workspace id") if team_id.blank?

      # Enforce 1 workspace : 1 company. The Slack events endpoint is keyed by
      # team_id (globally unique slug), so a workspace must belong to exactly one
      # company — otherwise a second install would hijack the first's event routing.
      if foreign_company_owns_workspace?(team_id)
        return save_error(build_integration, "This Slack workspace is already connected to another organization")
      end

      integration = find_or_build_for_team(team_id)
      integration.connected_by = @connected_by
      integration.name = team["name"].presence || "Slack"
      integration.credentials_data = {
        "bot_token"   => data["access_token"],
        "bot_user_id" => data["bot_user_id"],
        "team_id"     => team_id,
        "scope"       => data["scope"]
      }
      # team_id is non-secret and lives in `settings` so inbound events can be
      # routed by `settings->>'team_id'` without decrypting every install.
      integration.settings = integration.settings.to_h
        .merge("team_id" => team_id, "team_name" => team["name"])
        .except("error")
      integration.status = :active
      integration.save!
      provision_endpoint(integration, team_id)
      integration
    rescue Slack::Client::Error => e
      save_error(build_integration, "Slack OAuth failed: #{e.message}")
    rescue ActiveRecord::RecordNotUnique
      # Lost a race to another company claiming the same workspace's endpoint slug.
      save_error(build_integration, "This Slack workspace is already connected to another organization")
    rescue ActiveRecord::RecordInvalid => e
      save_error(build_integration, e.message)
    end

    private

    # A Slack install belongs to the COMPANY (project_id: nil) and serves every
    # project — connecting from any project reuses the one company-wide install,
    # and a company can connect several different workspaces (one per team_id).
    def build_integration
      @company.integrations.build(provider: :slack, connected_by: @connected_by, project: nil)
    end

    # Anchor a WebhookEndpoint for this install, keyed by team_id, so inbound
    # Slack events (one shared Request URL) route to the right project +
    # integration via Webhooks::ProcessEventJob. Verification is central (the app
    # signing secret), so no per-endpoint secret is stored.
    # True if another company already owns this workspace's events endpoint.
    def foreign_company_owns_workspace?(team_id)
      endpoint = WebhookEndpoint.find_by(slug: "slack-team-#{team_id}")
      endpoint.present? && endpoint.company_id.present? && endpoint.company_id != @company.id
    end

    def provision_endpoint(integration, team_id)
      endpoint = WebhookEndpoint.find_or_initialize_by(slug: "slack-team-#{team_id}")
      # Race-safe re-check: never reassign an endpoint owned by another company.
      if endpoint.persisted? && endpoint.company_id.present? && endpoint.company_id != @company.id
        raise ActiveRecord::RecordNotUnique, "Slack workspace owned by another company"
      end

      endpoint.assign_attributes(
        provider: :slack,
        verification_strategy: :slack_v0,
        project: nil, # company-scoped: the workspace serves all the company's projects
        company: @company,
        created_by: @connected_by,
        enabled: true,
        config: endpoint.config.to_h.merge("integration_id" => integration.id, "team_id" => team_id)
      )
      endpoint.save!
    end

    # One install per (company, team_id): reconnecting the same workspace (from any
    # project) updates the existing record (refreshed token) rather than
    # duplicating it; a different team_id yields a separate company-wide install.
    def find_or_build_for_team(team_id)
      @company.integrations
        .where(provider: :slack, project_id: nil)
        .find { |i| i.settings.to_h["team_id"].to_s == team_id } || build_integration
    end

    def save_error(integration, message)
      integration.name = integration.name.presence || "Slack"
      integration.status = :error
      integration.settings = integration.settings.to_h.merge("error" => message)
      integration.save
      integration
    end
  end
end
