# frozen_string_literal: true

module Bitbucket
  # The credential a connection's calls and clones use: the installation's
  # pushed app token in app mode, the pasted token in token mode.
  class CredentialProvider
    def initialize(integration)
      @integration = integration
    end

    def credential
      @integration.bitbucket_app? ? app_credential : token_credential
    end

    def client(**) = Client.new(credential: credential, **)

    private

    def app_credential(previous: nil)
      installation = live_installation!
      installation.reload if previous
      token = installation.usable_token(min_remaining: AppConfig.token_min_remaining)
      unless token
        raise Error::CredentialUnavailable, "The Aixle Flow app on Bitbucket workspace " \
                                            "#{installation.workspace_slug || installation.workspace_uuid} has not " \
                                            "delivered a usable token#{silence(installation)}."
      end
      return if previous && token == previous

      Credential.new(token: token, kind: :app, refresher: -> { refreshed(token) })
    end

    def refreshed(previous)
      app_credential(previous: previous)
    rescue Error::CredentialUnavailable
      nil
    end

    def live_installation!
      installation = @integration.bitbucket_installation
      raise Error::CredentialUnavailable, "This Bitbucket connection has no app installation." unless installation
      raise Error::CredentialUnavailable, "The Aixle Flow app was removed from this workspace." if installation.uninstalled?
      unless installation.bound? && installation.company_id == @integration.company_id
        raise Error::CredentialUnavailable, "This Bitbucket workspace is no longer connected to this company."
      end

      installation
    end

    def silence(installation)
      return "" unless installation.last_invocation_at

      " (last heard from #{ActionController::Base.helpers.time_ago_in_words(installation.last_invocation_at)} ago)"
    end

    def token_credential
      token = @integration.credentials_data["token"].presence
      raise Error::CredentialUnavailable, "This Bitbucket connection has no token." unless token

      Credential.new(token: token, kind: @integration.bitbucket_token_kind == "api_token" ? :api_token : :access_token)
    end
  end
end
