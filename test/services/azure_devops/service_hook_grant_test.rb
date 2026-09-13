# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # The one grant that turns the event path on. Azure gives *Edit subscriptions*
  # to project administrators only, so without this the application can never
  # create a Service Hook and CI gates fall back to the recovery sweep.
  #
  # WebMock rather than a fake: this is an adapter contract test, and the thing
  # worth pinning is the exact request Azure receives.
  class ServiceHookGrantTest < ActiveSupport::TestCase
    IDENTITIES = "https://vssps.dev.azure.com"

    setup do
      with_azure_devops_enabled
      @tenant = "79e1cf7c-9e26-468d-81f6-ce6f3b9783dd"
      @oid = "9550df62-80e0-4551-821e-ba38e4a7e876"
      @project = SecureRandom.uuid
      @grant = ServiceHookGrant.new(organization: "contoso", personal_access_token: "admin-pat",
                                    tenant_id: @tenant, principal_object_id: @oid)
    end

    def stub_identity(descriptor: "Microsoft.VisualStudio.Services.Claims.AadServicePrincipal;t\\o", value: nil)
      stub_request(:get, %r{#{IDENTITIES}/contoso/_apis/identities})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: value || [ { descriptor: descriptor } ] }.to_json)
    end

    def stub_ace(status: 200, body: { count: 1 }, headers: { "Content-Type" => "application/json" })
      stub_request(:post, %r{#{AZURE_API_HOST}/contoso/_apis/accesscontrolentries/#{ServiceHookGrant::NAMESPACE_ID}})
        .to_return(status: status, headers: headers, body: body.is_a?(String) ? body : body.to_json)
    end

    test "grants view and edit on the project's service hooks, and nothing else" do
      stub_identity(descriptor: "aad-sp-descriptor")
      stub_ace

      @grant.call([ @project ])

      assert_requested(:post, %r{/_apis/accesscontrolentries/#{ServiceHookGrant::NAMESPACE_ID}}) do |req|
        body = JSON.parse(req.body)
        ace = body["accessControlEntries"].first
        body["token"] == "PublisherSecurity/#{@project}" &&
          body["merge"] == true &&
          ace["descriptor"] == "aad-sp-descriptor" &&
          # View (1) | Edit (2). Delete (4) is deliberately absent — Edit can
          # already remove a subscription, so the bit would buy nothing.
          ace["allow"] == 3 &&
          ace["deny"] == 0
      end
    end

    test "one access control entry per approved project" do
      second = SecureRandom.uuid
      stub_identity
      stub_ace

      @grant.call([ @project, second ])

      assert_requested(:post, %r{/accesscontrolentries/}, times: 2)
    end

    # An identity entitled a moment ago may not be queryable yet. Failing here
    # would turn a propagation delay into a permanently missing grant, so the
    # descriptor Azure uses for an AAD service principal is assembled instead.
    test "falls back to the standard descriptor when the identity is not queryable yet" do
      stub_identity(value: [])
      stub_ace

      @grant.call([ @project ])

      assert_requested(:post, %r{/accesscontrolentries/}) do |req|
        JSON.parse(req.body)["accessControlEntries"].first["descriptor"] ==
          "Microsoft.VisualStudio.Services.Claims.AadServicePrincipal;#{@tenant}\\#{@oid}"
      end
    end

    # The failure a caller can actually act on: the token is real but was made
    # without Security (manage), so the message has to name the scope.
    test "a token without the security scope is refused with the scope named" do
      stub_identity
      stub_ace(status: 403, body: {})

      error = assert_raises(NotAuthorized) { @grant.call([ @project ]) }

      assert_match(/Security \(manage\)/, error.message)
    end

    # Azure answers a bad credential with a redirect to an HTML sign-in page
    # rather than a 401 — the same trap as everywhere else in this adapter.
    test "a sign-in page is read as an invalid token, not as a provider error" do
      stub_identity
      stub_ace(status: 302, body: "<html>sign in</html>", headers: { "Content-Type" => "text/html" })

      error = assert_raises(NotAuthorized) { @grant.call([ @project ]) }

      assert_match(/not valid for/, error.message)
    end

    test "an unexpected status is a coded error rather than a raw provider message" do
      stub_identity
      stub_ace(status: 500, body: {})

      error = assert_raises(Error) { @grant.call([ @project ]) }

      assert_equal "service_hook_grant_failed", error.code
    end

    test "nothing is attempted without a token or a service principal" do
      assert_raises(ValidationFailed) do
        ServiceHookGrant.new(organization: "contoso", personal_access_token: "",
                             tenant_id: @tenant, principal_object_id: @oid).call([ @project ])
      end

      assert_raises(ValidationFailed) do
        ServiceHookGrant.new(organization: "contoso", personal_access_token: "pat",
                             tenant_id: @tenant, principal_object_id: nil).call([ @project ])
      end
    end
  end
end
