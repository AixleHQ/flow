# frozen_string_literal: true

require "test_helper"

module Bitbucket
  module Forge
    class PairingTest < ActiveSupport::TestCase
      include ForgeTestHelper

      setup do
        with_bitbucket_settings(app_mode: true)
        @installation = create(:bitbucket_installation, :with_token, workspace_slug: "acme", workspace_name: "Acme")
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @project = create(:project, company: @company, owner: @user, name: "Platform")
      end

      def start
        stub_workspace_permission(@installation)
        url = Pairing.start!(installation: @installation, account_id: FORGE_ADMIN_ACCOUNT)
        public_id, secret = url.split("#pairing=").last.split(".", 2)
        [ url, BitbucketPairing.open(public_id, secret) ]
      end

      test "a workspace administrator gets a single-use link with the secret in its fragment" do
        url, pairing = start

        assert url.start_with?("#{Settings.protocol}://#{Settings.domain}/integrations/bitbucket/connect#pairing=")
        assert_equal FORGE_ADMIN_ACCOUNT, pairing.account_id
        assert_in_delta 10.minutes.from_now, pairing.expires_at, 5
        assert_not_includes BitbucketPairing.pluck(:secret_digest), url.split(".").last
      end

      test "anyone who is not a workspace administrator is refused" do
        stub_workspace_permission(@installation, permission: "member")

        error = assert_raises(Pairing::Refused) { Pairing.start!(installation: @installation, account_id: FORGE_ADMIN_ACCOUNT) }
        assert_equal "not_workspace_admin", error.code
        assert_equal 0, BitbucketPairing.count
      end

      test "an account id that could change the permission query is refused without asking" do
        assert_not WorkspaceAdmin.admin?(@installation, %(x" OR permission="owner))
      end

      test "confirming binds the workspace to the company and connects the project" do
        _, pairing = start
        stub_workspace_repositories(@installation)

        integration = Pairing.confirm!(pairing: pairing, user: @user, project: @project)

        assert_equal [ @company.id, @user.id ], @installation.reload.then { |i| [ i.company_id, i.bound_by_id ] }
        assert_equal [ "bitbucket", "app", "active", "Acme" ],
                     [ integration.provider, integration.bitbucket_auth_mode, integration.status, integration.name ]
        assert pairing.reload.consumed_at
      end

      test "a link works once" do
        _, pairing = start
        stub_workspace_repositories(@installation)
        Pairing.confirm!(pairing: pairing, user: @user, project: @project)

        error = assert_raises(Pairing::Refused) { Pairing.confirm!(pairing: pairing, user: @user, project: @project) }
        assert_equal "expired", error.code
      end

      test "an expired link connects nothing" do
        _, pairing = start

        travel 11.minutes do
          assert_nil BitbucketPairing.open(pairing.public_id, "anything")
          assert_raises(Pairing::Refused) { Pairing.confirm!(pairing: pairing, user: @user, project: @project) }
        end
        assert_not @installation.reload.bound?
      end

      test "a wrong secret opens nothing" do
        _, pairing = start

        assert_nil BitbucketPairing.open(pairing.public_id, "not-the-secret")
        assert_nil BitbucketPairing.open("unknown", nil)
      end

      test "a workspace bound to another company stays there" do
        _, pairing = start
        other = create(:company)
        @installation.update!(company: other)

        error = assert_raises(Pairing::Refused) { Pairing.confirm!(pairing: pairing, user: @user, project: @project) }
        assert_equal "bound_elsewhere", error.code
        assert_equal other.id, @installation.reload.company_id
        assert_nil pairing.reload.consumed_at
      end

      test "nothing is bound when the app cannot reach the workspace's repositories" do
        _, pairing = start
        stub_workspace_repositories(@installation, status: 403)

        assert_raises(Bitbucket::Error::PermissionDenied) { Pairing.confirm!(pairing: pairing, user: @user, project: @project) }
        assert_not @installation.reload.bound?
        assert_equal 0, Integration.where(provider: "bitbucket").count
      end

      test "after a reinstall the company's connections move to the new installation" do
        old = create(:integration, :bitbucket_app, :active, company: @company,
                                                            project: create(:project, company: @company, owner: @user))
        old_installation = old.bitbucket_installation
        Installations.uninstall!(old_installation)
        old_installation.update_columns(workspace_uuid: @installation.workspace_uuid)
        _, pairing = start
        stub_workspace_repositories(@installation)

        Pairing.confirm!(pairing: pairing, user: @user, project: @project)

        assert_equal [ @installation.id, "active" ], old.reload.then { |i| [ i.bitbucket_installation_id, i.status ] }
        assert_nil old.settings["error"]
      end

      test "the settings page sees which company and projects the workspace serves" do
        _, pairing = start
        stub_workspace_repositories(@installation)
        Pairing.confirm!(pairing: pairing, user: @user, project: @project)

        status = Pairing.status(@installation.reload)

        assert_equal [ true, @company.name, [ "Platform" ], @user.email ],
                     status.values_at(:bound, :company, :projects, :bound_by)
      end
    end
  end
end
