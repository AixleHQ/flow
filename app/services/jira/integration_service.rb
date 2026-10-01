# frozen_string_literal: true

module Jira
  # Connects a project to a Jira Cloud site, two ways:
  #
  # - Aixle's OAuth app (3LO): someone authorizes it at Atlassian; the callback
  #   stores the grant, and the connection is finished by picking the site and
  #   its projects. It acts as that person.
  # - A service account's OAuth credential (client credentials), pasted with the
  #   site URL. It acts as the service account.
  #
  # Either way the connection covers the Jira projects picked, and each becomes
  # a tracker (Trackers::Provisioning). Reconnecting a site the project already
  # has updates that connection in place, so its trackers and triggers stay.
  class IntegrationService
    class ConfigurationError < StandardError; end

    Inspection = Data.define(:site, :identity, :projects, :token)
    # A failed test that says nothing about the connection itself.
    TRANSIENT = %w[rate_limited timeout provider_error].freeze

    def initialize(company:, connected_by:, project:)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def inspect_service_account(site_url:, client_id:, client_secret:)
      raise ConfigurationError, "Enter the service account's client id and secret" if client_id.blank? || client_secret.blank?

      host = Oauth.site_host!(site_url)
      cloud_id = Oauth.cloud_id_for(host)
      token = Oauth.client_credentials(client_id: client_id, client_secret: client_secret)
      api = Api.new(Client.new(cloud_id: cloud_id, credential: StaticCredential.new(token["access_token"])))
      Inspection.new(site: { id: cloud_id, name: host, url: "https://#{host}" }, identity: api.myself,
                     projects: api.projects, token: token)
    end

    def connect_service_account(site_url:, client_id:, client_secret:, project_ids:)
      inspection = inspect_service_account(site_url: site_url, client_id: client_id, client_secret: client_secret)
      projects = chosen!(inspection.projects, project_ids)

      integration = existing(inspection.site[:id]) || build
      integration.credentials_data = inspection.token.merge("client_id" => client_id.to_s, "client_secret" => client_secret.to_s)
      integration.assign_attributes(
        name: "Jira · #{inspection.site[:name]}", status: :active, connected_by: @connected_by,
        settings: integration.settings.to_h.except("error", "sites").merge(
          "auth_mode" => "service_account", **site_settings(inspection.site),
          **identity_settings(inspection.identity, dedicated: true), "jira_projects" => projects
        )
      )
      integration.save!
      after_connect(integration)
    end

    # The 3LO callback. With one site granted, a connection this project already
    # has to it is renewed in place; otherwise a pending connection waits for
    # its site and projects (#configure).
    def connect_oauth(code:)
      raise ConfigurationError, "Jira's OAuth app is not configured on this deployment" unless AppConfig.oauth_enabled?

      token = Oauth.exchange_code(code)
      sites = Oauth.accessible_resources(token["access_token"])
      raise Error.new("This Atlassian account granted Aixle no Jira site", code: "not_found") if sites.empty?

      site = sites.one? ? sites.first : nil
      integration = (site && existing(site[:id])) || build
      integration.credentials_data = token
      settings = integration.settings.to_h.except("error").merge("auth_mode" => "oauth", "sites" => sites.map(&:stringify_keys))
      if site
        settings.merge!(site_settings(site))
        identity = Api.new(Client.new(cloud_id: site[:id], credential: StaticCredential.new(token["access_token"]))).myself
        settings.merge!(identity_settings(identity, dedicated: settings["dedicated_identity"] == true))
      end
      ready = site.present? && Array(settings["jira_projects"]).any?
      integration.assign_attributes(name: site ? "Jira · #{host_of(site[:url])}" : "Jira", settings: settings,
                                    status: ready ? :active : :inactive, connected_by: @connected_by)
      integration.save!
      ready ? after_connect(integration) : integration
    end

    # Finishes a pending 3LO connection, or changes a connection's projects.
    # `cloud_id` picks among the sites a 3LO grant covers.
    def configure(integration, project_ids:, cloud_id: nil, dedicated_identity: nil)
      settings = integration.settings.to_h
      if cloud_id.present? && cloud_id.to_s != settings["cloud_id"].to_s
        site = Array(settings["sites"]).find { |s| s["id"] == cloud_id.to_s }
        raise ConfigurationError, "Pick one of the sites Atlassian granted" unless site && settings["auth_mode"] == "oauth"
        raise ConfigurationError, "This project is already connected to #{site['name']}" if existing(cloud_id, except: integration)

        settings = settings.merge(site_settings(site.symbolize_keys)).except("jira_projects")
      end
      raise ConfigurationError, "Pick the Jira site first" if settings["cloud_id"].blank?

      integration.settings = settings
      api = Api.for(integration)
      projects = chosen!(api.projects, project_ids)
      dedicated = dedicated_identity.nil? ? settings["dedicated_identity"] == true : ActiveModel::Type::Boolean.new.cast(dedicated_identity)
      integration.assign_attributes(
        name: "Jira · #{host_of(settings['site_url'])}", status: :active,
        settings: settings.except("error").merge(identity_settings(api.myself, dedicated: dedicated), "jira_projects" => projects)
      )
      integration.save!
      after_connect(integration)
    end

    # What a pending or active connection can see, for the project picker.
    def available_projects(integration, cloud_id: nil)
      settings = integration.settings.to_h
      if cloud_id.present? && Array(settings["sites"]).none? { |s| s["id"] == cloud_id.to_s }
        raise ConfigurationError, "Pick one of the sites Atlassian granted"
      end

      site = cloud_id.presence || settings["cloud_id"]
      raise ConfigurationError, "Pick the Jira site first" if site.blank?

      credential = StaticCredential.new(Credential.new(integration).access_token)
      Api.new(Client.new(cloud_id: site, credential: credential)).projects
    end

    def test(integration)
      api = Api.for(integration)
      identity = api.myself
      visible = api.projects.index_by { |p| p[:id] }
      settings = integration.settings.to_h
      projects = Array(settings["jira_projects"]).map { |p| visible[p["id"].to_s]&.stringify_keys || p }
      missing = Array(settings["jira_projects"]).reject { |p| visible.key?(p["id"].to_s) }.pluck("key")
      integration.update!(status: :active, settings: settings.except("error").merge(
        identity_settings(identity, dedicated: settings["dedicated_identity"] == true), "jira_projects" => projects,
        "last_verified_at" => Time.current.iso8601
      ))
      after_connect(integration)
      { status: :active, missing: missing }
    rescue Error => e
      unless TRANSIENT.include?(e.code)
        integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => e.code),
                                   updated_at: Time.current)
      end
      { status: :error, error: e.code, message: e.message }
    end

    private

    def build
      raise ConfigurationError, "Jira connects to a project" unless @project

      @company.integrations.build(provider: :jira, project: @project, connected_by: @connected_by)
    end

    def existing(cloud_id, except: nil)
      scope = @company.integrations.where(provider: :jira, project_id: @project&.id)
                      .where("settings ->> 'cloud_id' = ?", cloud_id.to_s)
      scope = scope.where.not(id: except.id) if except
      scope.first
    end

    def chosen!(visible, project_ids)
      ids = Array(project_ids).map(&:to_s).compact_blank.uniq
      raise ConfigurationError, "Choose at least one Jira project" if ids.empty?

      by_id = visible.index_by { |p| p[:id] }
      unknown = ids.reject { |id| by_id.key?(id) }
      raise ConfigurationError, "This connection cannot see #{unknown.size} of the chosen projects" if unknown.any?

      ids.map { |id| by_id[id].slice(:id, :key, :name).stringify_keys }
    end

    def site_settings(site)
      { "cloud_id" => site[:id].to_s, "site_url" => site[:url].to_s.chomp("/"), "site_name" => site[:name].to_s }
    end

    # Who the connection acts as. Only an account kept for Aixle is its tracker
    # identity: a person's own edits must not pass for Aixle's.
    def identity_settings(identity, dedicated:)
      TrackerAccount.remember!(provider: "jira", account_ids: [ identity[:id] ])
      {
        "identity_display_name" => identity[:name], "dedicated_identity" => dedicated,
        "tracker_identity" => { "id" => identity[:id], "name" => identity[:name] }.compact
      }
    end

    def host_of(url)
      URI.parse(url.to_s).host || url.to_s
    rescue URI::InvalidURIError
      url.to_s
    end

    # Trackers follow the projects: new ones are provisioned, dropped ones detached.
    def after_connect(integration)
      Trackers::Provisioning.ensure_for!(integration)
      covered = Array(integration.settings.to_h["jira_projects"]).map { |p| p["id"].to_s }
      integration.project_trackers.where.not(status: "detached").where.not(external_scope_id: covered).find_each(&:detach!)
      if integration.settings.to_h["auth_mode"] == "service_account" || awaited?(integration)
        Trackers::Jira::Subscriptions.new(integration).ensure!
      end
      integration
    end

    def awaited?(integration)
      TriggerBinding.active.where(project_id: integration.project_id, event_type: Trackers::EventPipeline::EVENT_TYPES).exists?
    end
  end
end
