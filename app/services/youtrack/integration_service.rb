# frozen_string_literal: true

module Youtrack
  # Connects a project to a YouTrack instance — Cloud or self-hosted — through
  # the Aixle Flow app: the app provisions a service user, mints its permanent
  # token and hands it over when a pairing completes (YoutrackPairing). Each
  # YouTrack project chosen becomes a tracker (Trackers::Provisioning) with an
  # `app` subscription the app posts that project's events to.
  #
  # Completing a pairing for an instance the project already has replaces the
  # token in place, so its trackers, subscriptions and triggers stay.
  class IntegrationService
    class ConfigurationError < StandardError; end

    # A failed test that says nothing about the connection itself.
    TRANSIENT = %w[rate_limited timeout provider_error].freeze

    def initialize(company:, connected_by:, project:)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    # The token is checked against the instance it claims to come from before
    # anything is stored: it must act as the app's service user and see every
    # project chosen. `project_ids` is the whole set the connection covers.
    def connect_app(base_url:, token:, login:, project_ids:, app_version: nil)
      url = base_url!(base_url)
      raise ConfigurationError, "The app sent no token" if token.blank?

      api = Api.new(Client.new(base_url: url, token: token.to_s.strip))
      identity = api.me
      unless login.present? && identity[:login].to_s.casecmp?(login.to_s)
        raise ConfigurationError, "The token does not act as the Aixle Flow service user"
      end

      projects = chosen!(api, api.projects, project_ids)
      integration = existing(url) || build
      integration.credentials_data = { "permanent_token" => token.to_s.strip }
      integration.assign_attributes(
        name: "YouTrack · #{URI.parse(url).host}", status: :active, connected_by: @connected_by,
        settings: integration.settings.to_h.except("error", "dedicated_identity").merge(
          "auth_mode" => "app", "app_version" => app_version.to_s.presence, "base_url" => url,
          **identity_settings(identity), "youtrack_projects" => projects, "last_verified_at" => Time.current.iso8601
        ).compact
      )
      integration.save!
      after_connect(integration)
    end

    def test(integration)
      api = Api.for(integration)
      identity = api.me
      visible = api.projects.index_by { |p| p[:id] }
      settings = integration.settings.to_h
      covered = Array(settings["youtrack_projects"])
      projects = covered.map { |p| visible[p["id"].to_s] ? p.merge(visible[p["id"].to_s].slice(:key, :name).stringify_keys) : p }
      missing = covered.reject { |p| visible.key?(p["id"].to_s) }.pluck("key")
      integration.update!(status: :active, settings: settings.except("error").merge(
        identity_settings(identity), "youtrack_projects" => projects, "last_verified_at" => Time.current.iso8601
      ))
      after_connect(integration)
      warning = missing.any? ? "This connection can no longer see #{missing.join(', ')}" : nil
      warning ? { status: :active, warning: true, message: warning } : { status: :active }
    rescue Trackers::Error => e
      unless TRANSIENT.include?(e.code)
        integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => e.code),
                                   updated_at: Time.current)
      end
      { status: :error, error: e.code, message: e.message }
    end

    private

    def base_url!(url)
      normalized = Config.normalize_base_url(url)
      raise ConfigurationError, "Enter the YouTrack URL, for example https://acme.youtrack.cloud" unless normalized
      raise ConfigurationError, "The YouTrack URL must use https" unless normalized.start_with?("https://")

      normalized
    end

    def build
      raise ConfigurationError, "YouTrack connects to a project" unless @project

      @company.integrations.build(provider: :youtrack, project: @project, connected_by: @connected_by)
    end

    def existing(base_url)
      @company.integrations.where(provider: :youtrack, project_id: @project&.id)
              .where("settings ->> 'base_url' = ?", base_url).first
    end

    # Each chosen project with the fields its status and assignee are read
    # from: the state field (State, unless renamed) and Assignee.
    def chosen!(api, visible, project_ids)
      ids = Array(project_ids).map(&:to_s).compact_blank.uniq
      raise ConfigurationError, "Choose at least one YouTrack project" if ids.empty?

      by_id = visible.index_by { |p| p[:id] }
      unknown = ids.reject { |id| by_id.key?(id) }
      raise ConfigurationError, "The service user cannot see #{unknown.size} of the chosen projects" if unknown.any?

      ids.map do |id|
        fields = api.project_fields(id)
        states = fields.select { |f| f[:field_type].start_with?("state") }
        users = fields.select { |f| f[:field_type].start_with?("user") }
        by_id[id].slice(:id, :key, :name).stringify_keys.merge(
          "status_field" => (states.find { |f| f[:name] == "State" } || states.first)&.dig(:name),
          "assignee_field" => (users.find { |f| f[:name] == "Assignee" } || users.first)&.dig(:name)
        ).compact
      end
    end

    # The app's service user is always Aixle's own identity.
    def identity_settings(identity)
      {
        "identity_display_name" => identity[:name], "identity_login" => identity[:login],
        "tracker_identity" => { "id" => identity[:id], "name" => identity[:name], "login" => identity[:login] }.compact
      }
    end

    # Trackers follow the projects: new ones are provisioned, dropped ones detached.
    def after_connect(integration)
      Trackers::Provisioning.ensure_for!(integration)
      covered = Array(integration.settings.to_h["youtrack_projects"]).map { |p| p["id"].to_s }
      integration.project_trackers.where.not(status: "detached").where.not(external_scope_id: covered).find_each(&:detach!)
      Trackers::Youtrack::Subscriptions.new(integration).ensure!
      integration
    end
  end
end
