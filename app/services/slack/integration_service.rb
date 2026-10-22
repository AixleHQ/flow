# frozen_string_literal: true

module Slack
  # Connects a Slack workspace to a (company, project) via OAuth v2. Aixle runs
  # ONE Slack app per deployment (app credentials in Settings.slack.*); each
  # company installs it into its own workspace with one click, yielding a
  # per-workspace bot token. The install is keyed by `team_id` (stored in
  # `settings` for inbound routing) and the bot token lives in encrypted
  # `credentials_data`. A refused install saves nothing: the returned record is
  # unsaved, in :error, and carries the reason in `settings["error"]`.
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
      return refused("Slack did not return a workspace id") if team_id.blank?

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
        .merge({ "bot_name" => Chat::SlackProvider.bot_name(data["access_token"]) }.compact)
        .except("error")
      integration.status = :active
      Integration.transaction do
        integration.save!
        share_token_with_peers(integration)
        provision_endpoint(integration, team_id)
      end
      integration
    rescue Slack::Client::Error => e
      refused("Slack OAuth failed: #{e.message}")
    rescue ActiveRecord::RecordNotUnique
      # Lost a race to another install of the same workspace creating its endpoint.
      refused("Slack was being connected to this workspace at the same moment — connect again")
    rescue ActiveRecord::RecordInvalid => e
      refused(e.message)
    end

    private

    # A Slack install belongs to the COMPANY (project_id: nil) and serves every
    # project — connecting from any project reuses the one company-wide install,
    # and a company can connect several different workspaces (one per team_id).
    def build_integration
      @company.integrations.build(provider: :slack, connected_by: @connected_by, project: nil)
    end

    # Every company that connected the workspace speaks through the same bot,
    # so whichever of them installed last hands its token to the rest. An
    # uninstall had switched them all off; this switches them back on.
    def share_token_with_peers(integration)
      return if integration.chat_workspace.nil?

      integration.chat_workspace.integrations.where(provider: :slack).where.not(id: integration.id).find_each do |peer|
        peer.update!(credentials_data: integration.credentials_data, status: :active)
      end
      integration.chat_workspace.update!(status: "active")
    end

    # The workspace's one events endpoint (one shared Request URL, keyed by
    # team_id). It keeps hearing through the install it already names while that
    # serves the same workspace; verification is central (the app signing
    # secret), so no per-endpoint secret is stored.
    def provision_endpoint(integration, team_id)
      endpoint = WebhookEndpoint.find_or_initialize_by(slug: "slack-team-#{team_id}")
      current = endpoint.chat_install if endpoint.persisted?
      hears = current&.chat_workspace_id.present? && current.chat_workspace_id == integration.chat_workspace_id ? current : integration

      endpoint.assign_attributes(
        provider: :slack,
        verification_strategy: :slack_v0,
        project: nil, # the workspace serves every project of every company that connected it
        company: hears.company,
        enabled: true,
        config: endpoint.config.to_h.merge("integration_id" => hears.id, "team_id" => team_id,
                                           "chat_workspace_id" => integration.chat_workspace_id)
      )
      endpoint.created_by ||= @connected_by
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

    def refused(message)
      Integration.new(company: @company, provider: :slack, connected_by: @connected_by, name: "Slack",
                      status: :error, settings: { "error" => message })
    end
  end
end
