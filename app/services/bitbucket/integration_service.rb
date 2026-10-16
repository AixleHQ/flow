# frozen_string_literal: true

module Bitbucket
  # Connects a project to a Bitbucket workspace with a pasted token, replaces
  # that token, and re-checks a connection in either mode
  # (docs/design/bitbucket-integration.md §5.7).
  #
  # Two kinds of token arrive through one form, told apart by asking Bitbucket:
  # a scoped API token has a user (`/2.0/user` answers), a workspace, project or
  # repository access token is a bot with none, and is checked by reading the
  # workspace's repositories instead. A token Bitbucket refuses, or that cannot
  # be checked, is never saved.
  class IntegrationService
    # `code`: "invalid_workspace" or "validation_failed" (nothing to check),
    # "not_authorized" (Bitbucket
    # refused the token), "unreachable" (Bitbucket could not be asked),
    # "already_connected", or "wrong_workspace".
    class ConnectionError < StandardError
      attr_reader :code

      def initialize(message, code:)
        super(message)
        @code = code
      end
    end

    WORKSPACE = /\A[a-z0-9_-]{1,62}\z/
    REJECTED = "Bitbucket no longer accepts this connection's token. Replace the token."

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(workspace:, token:)
      token = token.to_s.strip
      info = verify!(workspace, token)
      integration = existing_for(info) || @company.integrations.build(provider: :bitbucket, project: @project)
      apply(integration, token, info)
      integration.save!
      integration
    end

    def replace_token(integration, token:)
      unless integration.bitbucket_token?
        raise ConnectionError.new("This connection uses the Aixle Flow app and has no token to replace.",
                                  code: "validation_failed")
      end

      token = token.to_s.strip
      info = verify!(integration.bitbucket_workspace_slug, token)
      if info[:workspace_uuid] != integration.bitbucket_workspace_uuid
        raise ConnectionError.new("This token is for another workspace. Connect that workspace separately.",
                                  code: "wrong_workspace")
      end
      if existing_for(info, except: integration)
        raise ConnectionError.new("This token's identity already has another Bitbucket connection here. " \
                                  "Replace the token on that one.", code: "already_connected")
      end

      apply(integration, token, info)
      integration.save!
      integration
    end

    # Re-checks the connection. Only Bitbucket refusing the credential marks it
    # for attention: an unreachable Bitbucket says nothing about the token, and a
    # silent app is the installation's problem, reported but not recorded here.
    def test(integration)
      integration.bitbucket_app? ? test_app(integration) : test_token(integration)
    end

    private

    def test_token(integration)
      api = Api.for(integration)
      if integration.bitbucket_token_kind == "api_token"
        api.current_user
      else
        api.first_repository(integration.bitbucket_workspace_uuid)
      end
      integration.update!(status: :active,
                          settings: integration.settings.to_h.except("error").merge("last_verified_at" => Time.current.iso8601))
      { status: :active }
    rescue Error::NotAuthorized, Error::PermissionDenied, Error::CredentialUnavailable => e
      integration.update_columns(status: "error", settings: integration.settings.to_h.merge("error" => REJECTED),
                                 updated_at: Time.current)
      { status: :error, error: "not_authorized", message: e.message }
    rescue Error => e
      { status: :error, error: "unreachable", message: e.message }
    end

    def test_app(integration)
      Api.for(integration).first_repository(integration.bitbucket_workspace_uuid)
      integration.update!(status: :active, settings: integration.settings.to_h.except("error"))
      { status: :active }
    rescue Error::CredentialUnavailable => e
      { status: :error, error: "integration_unavailable", message: e.message }
    rescue Error::NotAuthorized, Error::PermissionDenied => e
      { status: :error, error: "not_authorized", message: e.message }
    rescue Error => e
      { status: :error, error: "unreachable", message: e.message }
    end

    def verify!(workspace, token)
      slug = workspace.to_s.strip.downcase
      raise ConnectionError.new("Enter the Bitbucket workspace the token belongs to.", code: "invalid_workspace") if slug.blank?
      unless slug.match?(WORKSPACE)
        raise ConnectionError.new("#{slug} is not a Bitbucket workspace ID — use the one in bitbucket.org/<workspace>.",
                                  code: "invalid_workspace")
      end
      raise ConnectionError.new("Enter a Bitbucket access token or API token.", code: "validation_failed") if token.blank?

      api = Api.new(Credential.new(token: token, kind: :access_token))
      user = user_of(api)
      user ? api_token_info(api, slug, user) : access_token_info(api, slug)
    rescue Error::NotAuthorized, Error::PermissionDenied
      raise ConnectionError.new("Bitbucket rejected this token. It is mistyped, expired, revoked, or not for #{slug}.",
                                code: "not_authorized")
    rescue Error::NotFound
      raise ConnectionError.new("This token cannot see the Bitbucket workspace #{slug}.", code: "not_authorized")
    rescue Error => e
      raise ConnectionError.new("Could not reach Bitbucket (#{e.code}).", code: "unreachable")
    end

    # Bitbucket answers an access token on `/2.0/user` with a refusal of the
    # endpoint, not of the token, so only a transport failure counts as one here.
    def user_of(api)
      api.current_user
    rescue Error::NotAuthorized, Error::PermissionDenied, Error::ValidationFailed, Error::NotFound
      nil
    end

    def api_token_info(api, slug, user)
      workspace = api.workspace(slug)
      { kind: "api_token", workspace_uuid: workspace[:uuid], workspace_slug: workspace[:slug] || slug,
        workspace_name: workspace[:name], account_uuid: user[:uuid], account_name: user[:display_name] }
    end

    # An access token has no identity to tell two of them apart by, so they are
    # told apart by what they reach: a repository access token sees one
    # repository, a workspace or project token more. Pasting a token with the
    # same reach again renews that connection; a token for another repository is
    # another connection, and replacing one must not cut the other off.
    def access_token_info(api, slug)
      sample = api.repository_sample(slug)
      workspace_uuid = sample.first&.dig(:workspace_uuid) || api.workspace(slug)[:uuid]
      raise Error::NotFound if workspace_uuid.blank?

      single = sample.one? ? sample.first : nil
      { kind: "access_token", workspace_uuid: workspace_uuid, workspace_slug: slug, workspace_name: slug,
        account_uuid: nil, account_name: nil, reach: single ? single[:uuid] : "workspace",
        reach_name: single&.dig(:full_name) }
    end

    def apply(integration, token, info)
      integration.credentials_data = { "token" => token }
      integration.assign_attributes(name: display_name(info), status: :active, connected_by: @connected_by,
                                    settings: identity(integration, info))
    end

    def display_name(info)
      return "#{info[:workspace_slug]} (#{info[:account_name]})" if info[:account_name].present?

      info[:reach_name].presence || info[:workspace_slug]
    end

    def identity(integration, info)
      integration.settings.to_h.except("error").merge(
        "auth_mode" => "token", "token_kind" => info[:kind], "workspace_uuid" => info[:workspace_uuid],
        "workspace_slug" => info[:workspace_slug], "account_uuid" => info[:account_uuid], "token_reach" => info[:reach]
      ).compact
    end

    # The row this identity already has in this scope: one access-token row per
    # workspace and reach, one API-token row per workspace and account.
    def existing_for(info, except: nil)
      rows = @company.integrations.where(provider: :bitbucket, project_id: @project&.id)
                     .where("settings ->> 'auth_mode' = 'token'")
                     .where("settings ->> 'workspace_uuid' = ?", info[:workspace_uuid])
                     .where("settings ->> 'token_kind' = ?", info[:kind])
      rows = rows.where("settings ->> 'account_uuid' = ?", info[:account_uuid]) if info[:account_uuid]
      rows = rows.where("settings ->> 'token_reach' = ?", info[:reach]) if info[:reach]
      rows = rows.where.not(id: except.id) if except
      rows.first
    end
  end
end
