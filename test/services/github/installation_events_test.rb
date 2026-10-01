# frozen_string_literal: true

require "test_helper"

module Github
  class InstallationEventsTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def connection(installation_id, company: @company, project: @project, status: :active, settings: {})
      integration = build(:integration, :github, company: company, project: project, connected_by: @user,
                                                 status: status, settings: settings)
      integration.credentials_data = { "installation_id" => installation_id.to_s }
      integration.save!
      integration
    end

    # One installation can serve several companies; GitHub uninstalled it for all of them.
    test "deleted takes down the installation's connections in every company" do
      Github::InstallationOwnership.stubs(:enforced?).returns(true)
      other_company = create(:company)
      other_project = create(:project, company: other_company, owner: create(:user, company: other_company))
      ours = connection(4242)
      theirs = connection(4242, company: other_company, project: other_project)

      Github::InstallationEvents.apply(action: "deleted", installation_id: 4242)

      [ ours, theirs ].each do |integration|
        integration.reload
        assert_equal "error", integration.status.to_s
        assert_equal "uninstalled", integration.settings["installation_state"]
        assert_equal Github::InstallationEvents::UNINSTALLED, integration.settings["error"]
      end
    end

    test "suspend takes a connection down and unsuspend brings it back" do
      integration = connection(4242, settings: { "auth_mode" => "app", "account_login" => "acme-corp" })

      Github::InstallationEvents.apply(action: "suspend", installation_id: 4242)

      integration.reload
      assert_equal "error", integration.status.to_s
      assert_equal Github::InstallationEvents::SUSPENDED, integration.settings["error"]

      Github::InstallationEvents.apply(action: "unsuspend", installation_id: 4242)

      integration.reload
      assert integration.active?
      assert_equal({ "auth_mode" => "app", "account_login" => "acme-corp" }, integration.settings)
    end

    # Unsuspending says nothing about a connection that failed for another reason.
    test "unsuspend leaves a connection in error for another reason alone" do
      integration = connection(4242, status: :error, settings: { "error" => "Invalid PEM format" })

      Github::InstallationEvents.apply(action: "unsuspend", installation_id: 4242)

      assert_equal "error", integration.reload.status.to_s
      assert_equal "Invalid PEM format", integration.settings["error"]
    end

    test "an uninstalled connection does not come back on unsuspend" do
      integration = connection(4242)
      Github::InstallationEvents.apply(action: "suspend", installation_id: 4242)
      Github::InstallationEvents.apply(action: "deleted", installation_id: 4242)

      Github::InstallationEvents.apply(action: "unsuspend", installation_id: 4242)

      assert_equal "error", integration.reload.status.to_s
      assert_equal "uninstalled", integration.settings["installation_state"]
    end

    test "other actions change nothing" do
      integration = connection(4242)

      Github::InstallationEvents.apply(action: "new_permissions_accepted", installation_id: 4242)

      assert integration.reload.active?
    end
  end
end
