# frozen_string_literal: true

require "test_helper"

module Bitbucket
  module Forge
    class InstallationsTest < ActiveSupport::TestCase
      include ForgeTestHelper
      include ActiveJob::TestHelper

      setup do
        with_bitbucket_settings(app_mode: true)
        stub_forge_keys!
      end

      def invocation(installation_id)
        InvocationToken.verify!("Bearer #{forge_invocation_token(installation_id: installation_id)}")
      end

      test "the first invocation records an unbound installation with its token" do
        installation_id = forge_installation_ari

        installation = nil
        assert_enqueued_with(job: RefreshBitbucketInstallationJob) do
          installation = Installations.record!(invocation(installation_id), system_token: forge_system_token,
                                                                            installer_account_id: "acct-9")
        end

        assert_not installation.bound?
        assert_equal ForgeTestHelper::FORGE_WORKSPACE_UUID, installation.workspace_uuid
        assert_equal BitbucketTestHelper::FORGE_ENVIRONMENT_ID, installation.forge_environment_id
        assert_equal "acct-9", installation.installer_account_id
        assert installation.usable_token(min_remaining: 300)
      end

      test "a reinstall retires the workspace's previous installation and takes its connections down" do
        old = create(:integration, :bitbucket_app, :active)
        old.bitbucket_installation.update_columns(workspace_uuid: ForgeTestHelper::FORGE_WORKSPACE_UUID)

        fresh = Installations.record!(invocation(forge_installation_ari), system_token: forge_system_token)

        assert old.bitbucket_installation.reload.uninstalled?
        assert_nil old.bitbucket_installation.encrypted_access_token
        assert_equal "error", old.reload.status
        assert_equal "uninstalled", old.settings["installation_state"]
        assert fresh.active?
      end

      test "uninstalling clears the token and puts every connection in error" do
        integration = create(:integration, :bitbucket_app, :active)

        Installations.uninstall!(integration.bitbucket_installation)

        assert_nil integration.bitbucket_installation.reload.usable_token(min_remaining: 0)
        assert_equal "error", integration.reload.status
        assert_equal Installations::REMOVED, integration.settings["error"]
      end

      test "a late delivery for an uninstalled installation does not bring it back" do
        installation_id = forge_installation_ari
        installation = Installations.record!(invocation(installation_id), system_token: forge_system_token)
        Installations.uninstall!(installation)

        assert_nil Installations.record!(invocation(installation_id), system_token: forge_system_token)
        assert_nil installation.reload.token_expires_at
      end

      test "a token older than the one held is not stored" do
        installation_id = forge_installation_ari
        Installations.record!(invocation(installation_id), system_token: forge_system_token(expires_at: 3.hours.from_now))

        installation = Installations.record!(invocation(installation_id), system_token: forge_system_token(expires_at: 1.hour.from_now))

        assert_in_delta 3.hours.from_now, installation.token_expires_at, 5
      end
    end
  end
end
