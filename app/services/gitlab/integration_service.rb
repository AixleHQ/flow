# frozen_string_literal: true

module Gitlab
  # Connects a project to GitLab, two ways:
  #
  # - A personal (or group, or project) access token, pasted; replaced and
  #   re-checked here.
  # - The deployment's OAuth app, once: a group Owner consents, picks the group,
  #   and Flow creates a service account there whose token the connection keeps
  #   (docs/design/gitlab-tracker.md §4). The person's token is dropped.
  #
  # A connection is one GitLab account in one scope: connecting the same
  # account again renews that row, so its repositories stay attached. A token
  # GitLab refuses, or cannot be asked about, is never saved.
  #
  # The same connection can be a tracker: the projects and boards picked for it
  # (#configure_trackers) become trackers of the Flow project.
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
    PENDING_NAME = "GitLab · setting up"
    PENDING_MODE = "service_account_pending"
    SERVICE_ACCOUNT_MODE = "service_account"
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

    # The OAuth callback: a pending connection holds the person's token until
    # they pick the group for the service account (#create_service_account).
    def connect_oauth(code:, code_verifier:)
      unless AppConfig.oauth_enabled?
        raise ConnectionError.new("GitLab's OAuth app is not configured on this deployment", code: "validation_failed")
      end

      token = Oauth.exchange_code(code, code_verifier: code_verifier)
      setup = ServiceAccountSetup.new(Rest.new(token: token["access_token"]))
      person = setup.person
      groups = setup.owned_groups
      if groups.empty?
        raise ConnectionError.new("#{person[:username]} is not an Owner of any GitLab group. An Owner of the group whose " \
                                  "projects Flow should reach has to connect.", code: "validation_failed")
      end

      integration = @company.integrations.build(provider: :gitlab, project: @project, connected_by: @connected_by,
                                                name: PENDING_NAME, status: :inactive)
      integration.credentials_data = { "oauth_access_token" => token["access_token"] }
      integration.settings = { "auth_mode" => PENDING_MODE, "consented_by" => person[:username],
                               "gitlab_groups" => groups.map(&:stringify_keys) }
      integration.save!
      integration
    rescue Trackers::Error => e
      raise ConnectionError.new("GitLab: #{e.message}", code: e.code == "not_authorized" ? "not_authorized" : "unreachable")
    end

    # Spends the pending connection's OAuth token on a service account in the
    # chosen group and keeps only that account's token. Picking a group another
    # connection here already runs in renews that one instead.
    def create_service_account(integration, group_id:)
      settings = integration.settings.to_h
      group = Array(settings["gitlab_groups"]).find { |g| g["id"].to_s == group_id.to_s }
      raise ConnectionError.new("Pick one of the groups you own", code: "validation_failed") unless group

      oauth = integration.credentials_data["oauth_access_token"]
      raise ConnectionError.new("Sign in with GitLab again", code: "not_authorized") if oauth.blank?

      result = ServiceAccountSetup.new(Rest.new(token: oauth)).create!(group["id"])
      target = existing_for_group(group["id"], except: integration) || integration
      target.credentials_data = { "personal_access_token" => result.token[:token], "service_account_token_id" => result.token[:id] }
      target.assign_attributes(
        name: "GitLab · #{group['full_path']}", status: :active, connected_by: @connected_by,
        settings: target.settings.to_h.except("error", "gitlab_groups", "consented_by").merge(
          "auth_mode" => SERVICE_ACCOUNT_MODE, "gitlab_group" => group.slice("id", "full_path", "name"),
          "gitlab_user_id" => result.service_account[:id], "gitlab_username" => result.service_account[:username],
          "token_expires_at" => result.token[:expires_at], "last_verified_at" => Time.current.iso8601
        )
      )
      target.save!
      integration.destroy! unless target == integration
      target
    rescue Trackers::Error => e
      raise ConnectionError.new(service_account_refusal(e), code: e.code == "not_authorized" ? "not_authorized" : "validation_failed")
    end

    # The projects whose issues the connection can reach, for the tracker picker.
    def available_projects(integration)
      Rest.for(integration).paginate("/projects", { membership: true, with_issues_enabled: true, archived: false,
                                                    simple: true, order_by: "path", sort: "asc" }, limit: 500).map do |p|
        { id: p["id"].to_s, path: p["path_with_namespace"], name: p["name_with_namespace"] }
      end
    end

    def boards(integration, project_id)
      TrackerApi.for(integration).boards(project_id)
    end

    # The projects the connection tracks, each with its board: every one becomes
    # a tracker of this project, and one no longer chosen is detached.
    def configure_trackers(integration, trackers:)
      visible = available_projects(integration).index_by { |p| p[:id] }
      chosen = Array(trackers).map { |t| t.to_h.with_indifferent_access }.uniq { |t| t[:project_id].to_s }.map do |t|
        project = visible[t[:project_id].to_s]
        raise ConnectionError.new("This connection cannot see project #{t[:project_id]}", code: "validation_failed") unless project

        board = t[:board_id].presence && boards(integration, project[:id]).find { |b| b[:id] == t[:board_id].to_s }
        if t[:board_id].present? && board.nil?
          raise ConnectionError.new("#{project[:path]} has no board #{t[:board_id]}", code: "validation_failed")
        end

        { "id" => project[:id], "path" => project[:path], "name" => project[:name], "board_id" => board&.dig(:id),
          "board_name" => board&.dig(:name) }.compact
      end

      integration.update!(settings: integration.settings.to_h.merge("gitlab_trackers" => chosen))
      Trackers::Provisioning.ensure_for!(integration)
      integration.project_trackers.where.not(status: "detached").where.not(external_scope_id: chosen.pluck("id")).find_each(&:detach!)
      Trackers::Provider.for(integration).ensure_event_delivery!
      integration
    rescue Trackers::Error => e
      raise ConnectionError.new("GitLab: #{e.message}", code: "validation_failed")
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

    def existing_for_group(group_id, except:)
      @company.integrations.where(provider: :gitlab, project_id: @project&.id).where.not(id: except.id)
              .find_by("settings -> 'gitlab_group' ->> 'id' = ?", group_id.to_s)
    end

    def service_account_refusal(error)
      return "GitLab no longer accepts the sign-in. Sign in with GitLab again." if error.code == "not_authorized"
      return error.message unless error.code == "permission_denied"

      "GitLab did not let you create a service account in that group: it takes the group's Owner role (and, " \
        "on GitLab.com, a top-level group for an account there). #{error.message}"
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
