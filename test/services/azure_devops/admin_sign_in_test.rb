# frozen_string_literal: true

require "test_helper"

module AzureDevops
  class AdminSignInTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @cache = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(@cache)
      @tenant = "79e1cf7c-9e26-468d-81f6-ce6f3b9783dd"
      company = create(:company)
      @user = create(:user, :admin, company: company)
      @project = create(:project, company: company, owner: @user)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/git/repositories})
        .to_return(status: 302, headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{@tenant}" })
    end

    def delegated_token(tid: @tenant)
      "header.#{Base64.urlsafe_encode64({ tid: tid, upn: 'grace@contoso.com' }.to_json, padding: false)}.signature"
    end

    test "the sign-in goes to the organization's own directory, with PKCE and a signed state naming it" do
      uri = URI.parse(AdminSignIn.authorize_url(project: @project, user: @user, organization: "contoso"))
      query = Rack::Utils.parse_query(uri.query)

      assert_equal "#{AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_equal [ AdminSignIn::SCOPE, "code", "S256", AdminSignIn.redirect_uri ],
                   query.values_at("scope", "response_type", "code_challenge_method", "redirect_uri")
      state = Oauth::State.decode(query["state"])
      assert_equal [ "azure_devops", { "organization" => "contoso", "tenant_id" => @tenant } ], state.values_at("provider", "context")
    end

    test "the code is exchanged with the application's own credential for a delegated token" do
      stub_request(:post, "#{AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token")
        .with(body: hash_including("grant_type" => "authorization_code", "code" => "c1", "code_verifier" => "v1",
                                   "scope" => AdminSignIn::SCOPE))
        .to_return(status: 200, body: { access_token: delegated_token, token_type: "Bearer" }.to_json)

      credential = AdminSignIn.exchange!(code: "c1", tenant_id: @tenant, code_verifier: "v1")

      assert credential.sign_in?
      assert_equal [ @tenant, "grace@contoso.com" ], [ credential.tenant_id, credential.identity ]
      assert_equal "Bearer #{delegated_token}", credential.authorization
    end

    test "a refused code says why" do
      stub_request(:post, "#{AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token")
        .to_return(status: 400, body: { error: "invalid_grant", error_description: "AADSTS70008: The code has expired.\r\nTrace ID: x" }.to_json)

      error = assert_raises(NotAuthorized) { AdminSignIn.exchange!(code: "old", tenant_id: @tenant, code_verifier: "v") }
      assert_equal "Microsoft did not complete the sign-in (invalid_grant): AADSTS70008: The code has expired.", error.message
    end

    test "a held sign-in comes back only for the same person and organization" do
      handle = AdminSignIn.hold(AdminCredential.sign_in(delegated_token), user: @user, organization: "Contoso")

      assert_equal delegated_token, AdminSignIn.fetch(handle, user: @user, organization: "contoso").secret
      assert_nil AdminSignIn.fetch(handle, user: create(:user, company: @project.company), organization: "contoso")
      assert_nil AdminSignIn.fetch(handle, user: @user, organization: "fabrikam")
      assert_nil AdminSignIn.fetch("forged", user: @user, organization: "contoso")

      AdminSignIn.release(handle)
      assert_nil AdminSignIn.fetch(handle, user: @user, organization: "contoso")
    end
  end
end
