# frozen_string_literal: true

module Youtrack
  # Connects a project to a YouTrack instance — Cloud or self-hosted — with a
  # permanent token, which acts as its owner: best an account kept for Aixle.
  # Each YouTrack project picked becomes a tracker (Trackers::Provisioning), and
  # gets a manual subscription for its Webhook Triggers app.
  #
  # Connecting again to an instance the project already has replaces the token
  # in place, so its trackers, subscriptions and triggers stay.
  class IntegrationService
    class ConfigurationError < StandardError; end

    Inspection = Data.define(:base_url, :identity, :projects)
    # A failed test that says nothing about the connection itself.
    TRANSIENT = %w[rate_limited timeout provider_error].freeze

    # The login the connection acted as before a reconnect replaced its token
    # with another account's, when it did.
    attr_reader :previous_login

    def initialize(company:, connected_by:, project:)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def inspect_token(base_url:, token:)
      url = base_url!(base_url)
      raise ConfigurationError, "Enter the permanent token" if token.blank?

      api = Api.new(Client.new(base_url: url, token: token.to_s.strip))
      Inspection.new(base_url: url, identity: api.me, projects: api.projects)
    end

    def connect(base_url:, token:, project_ids:, dedicated_identity: false)
      inspection = inspect_token(base_url: base_url, token: token)
      api = Api.new(Client.new(base_url: inspection.base_url, token: token.to_s.strip))
      projects = chosen!(api, inspection.projects, project_ids)

      integration = existing(inspection.base_url) || build
      @previous_login = identity_change(integration, inspection.identity)
      integration.credentials_data = { "permanent_token" => token.to_s.strip }
      integration.assign_attributes(
        name: "YouTrack · #{URI.parse(inspection.base_url).host}", status: :active, connected_by: @connected_by,
        settings: integration.settings.to_h.except("error").merge(
          "auth_mode" => "permanent_token", "base_url" => inspection.base_url,
          **identity_settings(inspection.identity, dedicated: boolean(dedicated_identity)),
          "youtrack_projects" => projects, "last_verified_at" => Time.current.iso8601
        )
      )
      integration.save!
      after_connect(integration)
    end

    # Changes which projects a connection covers, or whether its account is kept for Aixle.
    def configure(integration, project_ids:, dedicated_identity: nil)
      api = Api.for(integration)
      projects = chosen!(api, api.projects, project_ids)
      settings = integration.settings.to_h
      dedicated = dedicated_identity.nil? ? settings["dedicated_identity"] == true : boolean(dedicated_identity)
      integration.update!(status: :active, settings: settings.except("error").merge(
        identity_settings(api.me, dedicated: dedicated), "youtrack_projects" => projects
      ))
      after_connect(integration)
    end

    def available_projects(integration)
      Api.for(integration).projects
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
        identity_settings(identity, dedicated: settings["dedicated_identity"] == true), "youtrack_projects" => projects,
        "last_verified_at" => Time.current.iso8601
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
      raise ConfigurationError, "This token cannot see #{unknown.size} of the chosen projects" if unknown.any?

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

    # Who the connection acts as. Only an account kept for Aixle is its tracker
    # identity: a person's own edits must not pass for Aixle's.
    def identity_settings(identity, dedicated:)
      {
        "identity_display_name" => identity[:name], "identity_login" => identity[:login], "dedicated_identity" => dedicated,
        "tracker_identity" => { "id" => identity[:id], "name" => identity[:name], "login" => identity[:login] }.compact
      }
    end

    def identity_change(integration, identity)
      before = integration.settings.to_h.dig("tracker_identity", "login")
      before if integration.persisted? && before.present? && !before.casecmp?(identity[:login].to_s)
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
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
