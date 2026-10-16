# frozen_string_literal: true

require "test_helper"

# Confirming, in Aixle, the Connect a Bitbucket workspace administrator started
# on the Aixle Flow settings page.
class Web::Integrations::BitbucketConnectTest < ActionDispatch::IntegrationTest
  include ForgeTestHelper

  setup do
    with_bitbucket_settings(app_mode: true)
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user, name: "Platform")
    @installation = create(:bitbucket_installation, :with_token, workspace_slug: "acme", workspace_name: "Acme")
    @pairing, @secret = BitbucketPairing.start!(installation: @installation, account_id: FORGE_ADMIN_ACCOUNT)
  end

  def pairing_params = { pairing_id: @pairing.public_id, pairing_secret: @secret }

  test "a guest gets the page, which sends them to sign in and back here" do
    get bitbucket_connect_path

    assert_inertia_page "Integrations/BitbucketConnect"
    assert_inertia_props do |props|
      assert props.key?(:signedIn)
      refute props[:signedIn]
      assert_equal login_path, props[:loginUrl]
      assert_empty props[:projects]
    end
  end

  test "signing in after opening the link as a guest comes back to the connect page" do
    get bitbucket_connect_path

    sign_in_as(@user)

    assert_redirected_to bitbucket_connect_path
  end

  test "a guest cannot preview or confirm a pairing" do
    post bitbucket_connect_preview_path, params: pairing_params, as: :json

    assert_redirected_to login_path
  end

  test "the page offers the projects the user can connect integrations in" do
    sign_in_as(@user)

    get bitbucket_connect_path

    assert_inertia_page "Integrations/BitbucketConnect"
    assert_inertia_props do |props|
      assert_equal [ "Platform" ], props[:projects].pluck(:name)
      assert_nil props[:preselectedProjectId]
    end
  end

  test "the preview names the workspace for the pairing the link carries" do
    sign_in_as(@user)

    post bitbucket_connect_preview_path, params: pairing_params, as: :json

    assert_response :ok
    assert_equal({ "slug" => "acme", "name" => "Acme" }, response.parsed_body["workspace"])
  end

  test "a wrong secret previews nothing" do
    sign_in_as(@user)

    post bitbucket_connect_preview_path, params: pairing_params.merge(pairing_secret: "guess"), as: :json

    assert_response :not_found
  end

  test "confirming connects the chosen project and sends the user to it" do
    sign_in_as(@user)
    stub_workspace_repositories(@installation)

    post integrations_bitbucket_connect_path, params: pairing_params.merge(project_id: @project.id), as: :json

    assert_response :ok
    assert_equal company_project_integrations_path(@project), response.parsed_body["redirect_url"]
    assert_equal @company.id, @installation.reload.company_id
    assert_equal 1, @project.company.integrations.where(provider: "bitbucket", project: @project).count
  end

  test "a project the user cannot connect integrations in is refused" do
    sign_in_as(@user)
    stranger = create(:company)
    other = create(:project, company: stranger, owner: create(:user, company: stranger))

    post integrations_bitbucket_connect_path, params: pairing_params.merge(project_id: other.id), as: :json

    assert_response :unprocessable_content
    assert_not @installation.reload.bound?
    assert BitbucketPairing.exists?(@pairing.id)
  end

  test "a workspace bound to another company is refused with the reason" do
    sign_in_as(@user)
    @installation.update!(company: create(:company))

    post integrations_bitbucket_connect_path, params: pairing_params.merge(project_id: @project.id), as: :json

    assert_response :unprocessable_content
    assert_equal "bound_elsewhere", response.parsed_body["error"]
  end
end
