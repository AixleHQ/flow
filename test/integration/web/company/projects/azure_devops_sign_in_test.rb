# frozen_string_literal: true

require "test_helper"

# "Sign in with Microsoft" instead of an administrator PAT, through the real
# endpoints: the start redirect, Microsoft's callback, and the dialog resuming
# with the held sign-in. Entra and Azure DevOps are WebMock-stubbed.
class Web::Company::Projects::AzureDevopsSignInTest < ActionDispatch::IntegrationTest
  ENTITLEMENTS = "https://vsaex.dev.azure.com"

  setup do
    with_azure_devops_enabled
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @tenant = "79e1cf7c-9e26-468d-81f6-ce6f3b9783dd"
    sign_in_as(@user)
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/git/repositories})
      .to_return(status: 302, headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{@tenant}" })
  end

  def delegated_token
    "header.#{Base64.urlsafe_encode64({ tid: @tenant, upn: 'grace@contoso.com' }.to_json, padding: false)}.signature"
  end

  test "an administrator signs in at Microsoft and the dialog resumes with the organization's projects" do
    get azure_devops_sign_in_company_project_integrations_path(@project, organization: "contoso")
    authorize = URI.parse(response.location)
    assert_equal [ "login.microsoftonline.com", "/#{@tenant}/oauth2/v2.0/authorize" ], [ authorize.host, authorize.path ]
    state = Rack::Utils.parse_query(authorize.query)["state"]
    stub_request(:post, "#{AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token")
      .to_return(status: 200, body: { access_token: delegated_token }.to_json)

    get azure_devops_oauth_callback_path, params: { code: "c1", state: state }

    resume = URI.parse(response.location)
    handle = Rack::Utils.parse_query(resume.query)["azure_setup"]
    assert_equal company_project_integrations_path(@project), resume.path
    assert handle.present?

    probe = stub_request(:get, %r{#{ENTITLEMENTS}/contoso/_apis/userentitlements})
            .with(headers: { "Authorization" => "Bearer #{delegated_token}" })
            .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { members: [] }.to_json)
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { value: [ { id: "p1", name: "Customer Platform" } ] }.to_json)

    post azure_devops_inspect_company_project_integrations_path(@project),
         params: { organization: "contoso", sign_in: handle }, as: :json

    assert_response :success
    assert_requested probe
    assert_equal [ "grace@contoso.com", [ "p1" ] ], [ response.parsed_body["identity"], response.parsed_body["projects"].pluck("id") ]
  end

  test "an expired or someone else's sign-in is refused" do
    post azure_devops_inspect_company_project_integrations_path(@project),
         params: { organization: "contoso", sign_in: "nope" }, as: :json

    assert_response :unprocessable_content
    assert_match(/sign-in has expired/, response.parsed_body["message"])
  end

  test "a directory that lets only administrators consent is explained" do
    get azure_devops_sign_in_company_project_integrations_path(@project, organization: "contoso")
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get azure_devops_oauth_callback_path,
        params: { state: state, error: "access_denied", error_description: "AADSTS65001: The user or administrator has not consented" }

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/only an administrator approve Aixle/, flash[:alert])
  end
end
