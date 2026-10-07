# frozen_string_literal: true

require "test_helper"

# Connecting YouTrack from a project: Aixle starts a pairing bound to it and
# sends the browser to the Aixle Flow app on the instance, which finishes it.
class Web::Company::Projects::YoutrackIntegrationsTest < ActionDispatch::IntegrationTest
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "connecting starts a pairing for this project and sends the browser to the app on the instance" do
    post youtrack_connect_company_project_integrations_path(@project), params: { instance_url: "https://Acme.youtrack.cloud/api/" },
                                                                       as: :json

    assert_response :success
    pairing = YoutrackPairing.sole
    assert_equal [ "aixle", "approved", @project, @user, "https://acme.youtrack.cloud" ],
                 [ pairing.origin, pairing.state, pairing.project, pairing.user, pairing.instance_url ]
    url, secret = response.parsed_body["redirect_url"].split("#app_pairing=")
    assert_equal "https://acme.youtrack.cloud/admin/app/aixle-flow/connect", url
    assert pairing.authentic?(secret.delete_prefix("#{pairing.public_id}."))
  end

  test "an http or missing URL starts nothing" do
    post youtrack_connect_company_project_integrations_path(@project), params: { instance_url: "http://acme.youtrack.cloud" }, as: :json

    assert_response :unprocessable_content
    assert_match(/https/, response.parsed_body["message"])
    assert_equal 0, YoutrackPairing.count
  end

  test "a connection's projects are not edited here, and its test reads the instance again" do
    integration = create(:integration, :youtrack, :active, project: @project, company: @company, connected_by: @user)

    patch company_project_integration_path(@project, integration), params: { project_ids: [ APP ] }
    assert_match(/Aixle Flow app/, flash[:alert])
    assert_equal [ APP, OPS ], integration.reload.settings["youtrack_projects"].pluck("id")

    post test_connection_company_project_integration_path(@project, integration)
    assert_equal "Connection verified", flash[:notice]
    assert @youtrack.called?(:me)
  end
end
