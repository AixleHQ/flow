# frozen_string_literal: true

require "test_helper"

module Bitbucket
  class CredentialProviderTest < ActiveSupport::TestCase
    setup { with_bitbucket_settings(app_mode: true) }

    test "token mode answers the pasted token under the access-token git username" do
      integration = create(:integration, :bitbucket, :active)

      credential = CredentialProvider.new(integration).credential

      assert_equal integration.credentials_data["token"], credential.token
      assert_equal "x-token-auth", credential.git_username
    end

    test "an API token clones under its own git username" do
      integration = create(:integration, :bitbucket_api_token, :active)

      assert_equal "x-bitbucket-api-token-auth", CredentialProvider.new(integration).credential.git_username
    end

    test "app mode answers the installation's pushed token" do
      integration = create(:integration, :bitbucket_app, :active)
      integration.bitbucket_installation.store_token!("pushed", expires_at: 4.hours.from_now)

      credential = CredentialProvider.new(integration).credential

      assert_equal "pushed", credential.token
      assert_equal :app, credential.kind
    end

    test "a stale installation fails fast, naming the workspace" do
      integration = create(:integration, :bitbucket_app, :active)
      integration.bitbucket_installation.clear_token!

      error = assert_raises(Error::CredentialUnavailable) { CredentialProvider.new(integration).credential }
      assert_includes error.message, integration.bitbucket_installation.workspace_slug
    end

    test "refresh offers a newer token only when one has landed" do
      integration = create(:integration, :bitbucket_app, :active)
      installation = integration.bitbucket_installation
      installation.store_token!("first", expires_at: 4.hours.from_now)
      credential = CredentialProvider.new(integration).credential

      assert_nil credential.refresh

      installation.store_token!("second", expires_at: 5.hours.from_now)
      assert_equal "second", credential.refresh.token
    end

    test "an installation unbound from the company stops serving its connections" do
      integration = create(:integration, :bitbucket_app, :active)
      integration.bitbucket_installation.update_columns(company_id: nil)

      assert_raises(Error::CredentialUnavailable) { CredentialProvider.new(integration.reload).credential }
    end
  end
end
