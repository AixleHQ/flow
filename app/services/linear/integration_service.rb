# frozen_string_literal: true

module Linear
  # Connects a project to a Linear workspace, two ways:
  #
  # - Aixle's OAuth app, which a workspace admin installs with actor=app: it
  #   acts as itself, and the app's own webhook delivers the workspace's events.
  #   The callback stores the grant; picking the teams finishes the connection.
  # - A personal API key, pasted with the teams to cover. It acts as the key's
  #   owner, so the account is best kept for Aixle; its events need a webhook
  #   per team, which only a workspace admin's key with the Admin permission can register.
  #
  # Either way each team becomes a tracker (Trackers::Provisioning).
  # Reconnecting a workspace the project already has updates that connection in
  # place, so its trackers and triggers stay.
  class IntegrationService
    class ConfigurationError < StandardError; end

    Inspection = Data.define(:identity, :teams)
    # A failed test that says nothing about the connection itself.
    TRANSIENT = %w[rate_limited timeout provider_error].freeze

    def initialize(company:, connected_by:, project:)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def inspect_api_key(api_key:)
      raise ConfigurationError, "Enter the Linear API key" if api_key.blank?

      api = Api.new(Client.new(credential: StaticCredential.api_key(api_key.to_s.strip)))
      Inspection.new(identity: api.identity, teams: api.teams)
    end

    def connect_api_key(api_key:, team_ids:, dedicated_identity: false)
      inspection = inspect_api_key(api_key: api_key)
      teams = chosen!(inspection.teams, team_ids)
      organization = inspection.identity[:organization]

      integration = existing(organization[:id]) || build
      integration.credentials_data = { "api_key" => api_key.to_s.strip }
      integration.assign_attributes(
        name: "Linear · #{organization[:name]}", status: :active, connected_by: @connected_by,
        settings: integration.settings.to_h.except("error").merge(
          "auth_mode" => "api_key", **organization_settings(organization),
          **identity_settings(inspection.identity, dedicated: boolean(dedicated_identity)), "linear_teams" => teams
        )
      )
      integration.save!
      after_connect(integration)
    end

    # The OAuth callback. A connection this project already has to the
    # workspace is renewed in place; otherwise a pending one waits for its teams
    # (#configure).
    def connect_oauth(code:)
      raise ConfigurationError, "Linear's OAuth app is not configured on this deployment" unless AppConfig.oauth_enabled?

      token = Oauth.exchange_code(code)
      identity = Api.new(Client.new(credential: StaticCredential.bearer(token["access_token"]))).identity
      organization = identity[:organization]

      integration = existing(organization[:id]) || build
      integration.credentials_data = token
      settings = integration.settings.to_h.except("error").merge(
        "auth_mode" => "oauth", **organization_settings(organization), **identity_settings(identity, dedicated: true)
      )
      ready = Array(settings["linear_teams"]).any?
      integration.assign_attributes(name: "Linear · #{organization[:name]}", settings: settings,
                                    status: ready ? :active : :inactive, connected_by: @connected_by)
      integration.save!
      ready ? after_connect(integration) : integration
    end

    # Finishes a pending OAuth connection, or changes a connection's teams.
    def configure(integration, team_ids:, dedicated_identity: nil)
      api = Api.for(integration)
      teams = chosen!(api.teams, team_ids)
      settings = integration.settings.to_h
      dedicated = if settings["auth_mode"] == "oauth" then true
      elsif dedicated_identity.nil? then settings["dedicated_identity"] == true
      else boolean(dedicated_identity)
      end
      integration.update!(status: :active, settings: settings.except("error").merge(
        identity_settings(api.identity, dedicated: dedicated), "linear_teams" => teams
      ))
      after_connect(integration)
    end

    def available_teams(integration)
      Api.for(integration).teams
    end

    def test(integration)
      api = Api.for(integration)
      identity = api.identity
      visible = api.teams.index_by { |t| t[:id] }
      settings = integration.settings.to_h
      teams = Array(settings["linear_teams"]).map { |t| visible[t["id"].to_s]&.stringify_keys || t }
      missing = Array(settings["linear_teams"]).reject { |t| visible.key?(t["id"].to_s) }.pluck("key")
      integration.update!(status: :active, settings: settings.except("error").merge(
        identity_settings(identity, dedicated: settings["dedicated_identity"] == true), "linear_teams" => teams,
        "last_verified_at" => Time.current.iso8601
      ))
      after_connect(integration)
      warning = test_warning(integration, missing)
      warning ? { status: :active, warning: true, message: warning } : { status: :active }
    rescue Trackers::Error => e
      unless TRANSIENT.include?(e.code)
        integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => e.code),
                                   updated_at: Time.current)
      end
      { status: :error, error: e.code, message: e.message }
    end

    private

    def build
      raise ConfigurationError, "Linear connects to a project" unless @project

      @company.integrations.build(provider: :linear, project: @project, connected_by: @connected_by)
    end

    def existing(organization_id)
      @company.integrations.where(provider: :linear, project_id: @project&.id)
              .where("settings ->> 'organization_id' = ?", organization_id.to_s).first
    end

    def chosen!(visible, team_ids)
      ids = Array(team_ids).map(&:to_s).compact_blank.uniq
      raise ConfigurationError, "Choose at least one Linear team" if ids.empty?

      by_id = visible.index_by { |t| t[:id] }
      unknown = ids.reject { |id| by_id.key?(id) }
      raise ConfigurationError, "This connection cannot see #{unknown.size} of the chosen teams" if unknown.any?

      ids.map { |id| by_id[id].slice(:id, :key, :name).stringify_keys }
    end

    def organization_settings(organization)
      { "organization_id" => organization[:id].to_s, "organization_name" => organization[:name].to_s,
        "url_key" => organization[:url_key].to_s }
    end

    # Who the connection acts as. Only an account kept for Aixle is its tracker
    # identity: a person's own edits must not pass for Aixle's.
    def identity_settings(identity, dedicated:)
      {
        "identity_display_name" => identity[:name], "dedicated_identity" => dedicated,
        "tracker_identity" => { "id" => identity[:id], "name" => identity[:name], "login" => identity[:display_name] }.compact
      }
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    # Trackers follow the teams: new ones are provisioned, dropped ones detached.
    def after_connect(integration)
      Trackers::Provisioning.ensure_for!(integration)
      covered = Array(integration.settings.to_h["linear_teams"]).map { |t| t["id"].to_s }
      integration.project_trackers.where.not(status: "detached").where.not(external_scope_id: covered).find_each(&:detach!)
      Trackers::Linear::Subscriptions.new(integration).ensure! if integration.settings.to_h["auth_mode"] == "oauth" || awaited?(integration)
      integration
    end

    def awaited?(integration)
      TriggerBinding.active.where(project_id: integration.project_id, event_type: Trackers::EventPipeline::EVENT_TYPES).exists?
    end

    def test_warning(integration, missing)
      return "This connection can no longer see #{missing.join(', ')}" if missing.any?

      failing = integration.tracker_subscriptions.where(status: "failing").pick(:last_error)
      "Events are not reaching Aixle: #{failing}" if failing
    end
  end
end
