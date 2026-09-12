# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Self-service onboarding: a company binds itself to an Azure organization by
  # proving it controls it, instead of an operator vouching from a console.
  #
  # The proof is the whole point, so most of this file is about what happens
  # when it is absent, wrong, or belongs to someone who is not an administrator.
  class OnboardingTest < ActiveSupport::TestCase
    ENTITLEMENTS = "https://vsaex.dev.azure.com"

    setup do
      with_azure_devops_enabled
      @company = create(:company)
      @actor = create(:user, :admin, company: @company)
      @tenant = "79e1cf7c-9e26-468d-81f6-ce6f3b9783dd"
      @project_id = SecureRandom.uuid
      @onboarding = Onboarding.new(company: @company, actor: @actor)
    end

    # Discovery hits an ORGANIZATION-level git endpoint, which nothing else in
    # the adapter touches — so this stub cannot be shadowed by the project
    # listings below.
    def stub_tenant(organization: "contoso", tenant: @tenant)
      stub_request(:get, %r{#{AZURE_API_HOST}/#{organization}/_apis/git/repositories})
        .to_return(status: 302,
                   headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{tenant}" })
    end

    def stub_admin_probe(status: 200, body: { members: [ { user: { principalName: "ada@contoso.com" } } ] })
      stub_request(:get, %r{#{ENTITLEMENTS}/contoso/_apis/userentitlements})
        .to_return(status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json)
    end

    def stub_admin_project_list
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects\?.*\$top})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ { id: @project_id, name: "Customer Platform" } ] }.to_json)
    end

    # == the proof ==

    test "a first bind without a token is refused before anything is written" do
      stub_tenant

      error = assert_raises(ValidationFailed) { @onboarding.inspect!(organization: "contoso") }
      assert_match(/personal access token/, error.message)
      assert_equal 0, AzureDevopsInstallation.count
    end

    # Azure answers an invalid credential with a 302 to an HTML sign-in page
    # rather than a 401, so "did we get JSON" is the rule rather than the status.
    test "a token Azure bounces to a sign-in page is reported as invalid, not as a provider error" do
      stub_tenant
      stub_request(:get, %r{#{ENTITLEMENTS}/contoso/_apis/userentitlements})
        .to_return(status: 302, headers: { "Content-Type" => "text/html" }, body: "<html>sign in</html>")

      error = assert_raises(NotAuthorized) do
        @onboarding.inspect!(organization: "contoso", personal_access_token: "bogus")
      end
      assert_match(/not valid for organization/, error.message)
    end

    # A real token from someone who is not an administrator. The message has to
    # distinguish this from a bad token, because the fix is different.
    test "a non-administrator token is refused with the reason" do
      stub_tenant
      stub_admin_probe(status: 403, body: {})

      error = assert_raises(NotAuthorized) do
        @onboarding.inspect!(organization: "contoso", personal_access_token: "valid-but-not-admin")
      end
      assert_match(/cannot administer/, error.message)
      assert_match(/Member Entitlement Management/, error.message)
    end

    test "an organization with no Entra directory says so rather than failing obscurely" do
      stub_request(:get, %r{#{AZURE_API_HOST}/msaorg/_apis/git/repositories}).to_return(status: 302, headers: {})

      error = assert_raises(TenantDiscovery::NoTenant) do
        @onboarding.inspect!(organization: "msaorg", personal_access_token: "x")
      end
      assert_equal "organization_has_no_tenant", error.code
      assert_match(/personal access token instead/, error.message)
    end

    # == the happy path ==

    test "inspect proves control and lists what the administrator can see" do
      stub_tenant
      stub_admin_probe
      stub_admin_project_list

      result = @onboarding.inspect!(organization: "contoso", personal_access_token: "admin-pat")

      assert_equal "contoso", result.organization
      assert_equal @tenant, result.tenant_id
      assert_equal "ada@contoso.com", result.identity
      refute result.already_bound
      assert_equal [ @project_id ], result.projects.map { |p| p[:id] }
      # Nothing is written during inspection.
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "complete entitles the application, confirms its access and records the binding" do
      stub_tenant
      stub_admin_probe
      stub_azure_token(tenant_id: @tenant, token: token_with_oid("9550df62-80e0-4551-821e-ba38e4a7e876"))
      stub_request(:post, %r{#{ENTITLEMENTS}/contoso/_apis/serviceprincipalentitlements})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { isSuccess: true }.to_json)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ { id: @project_id, name: "Customer Platform" } ] }.to_json)

      installation = @onboarding.complete!(organization: "contoso", personal_access_token: "admin-pat",
                                           project_ids: [ @project_id ])

      assert installation.active?
      assert_equal @company.id, installation.company_id
      assert_equal [ @project_id ], installation.allowed_project_ids
      assert_equal @actor.id, installation.approved_by_id
      # The object id came from the token's `oid` claim rather than from anyone
      # pasting it out of the portal.
      assert_equal "9550df62-80e0-4551-821e-ba38e4a7e876", installation.service_principal_object_id

      assert_requested(:post, %r{#{ENTITLEMENTS}/contoso/_apis/serviceprincipalentitlements}) do |req|
        body = JSON.parse(req.body)
        body.dig("accessLevel", "accountLicenseType") == "express" &&
          body.dig("servicePrincipal", "originId") == "9550df62-80e0-4551-821e-ba38e4a7e876" &&
          body["projectEntitlements"].first.dig("group", "groupType") == "projectContributor"
      end
    end

    # Entitlement is not always instant, and a binding recorded before the
    # application can actually read the project would fail on first use.
    test "a binding is not recorded while the application still cannot see the project" do
      stub_tenant
      stub_admin_probe
      stub_azure_token(tenant_id: @tenant, token: token_with_oid("oid-1"))
      stub_request(:post, %r{#{ENTITLEMENTS}/contoso/_apis/serviceprincipalentitlements})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json)

      error = assert_raises(Error) do
        @onboarding.complete!(organization: "contoso", personal_access_token: "admin-pat",
                              project_ids: [ @project_id ])
      end
      assert_equal "entitlement_not_effective", error.code
      assert_not_equal "active", AzureDevopsInstallation.find_by(company: @company)&.status.to_s
    end

    # == the second time ==

    test "an organization the company already holds needs no token at all" do
      bound = create(:azure_devops_installation, :active, :approved, company: @company,
                     tenant_id: @tenant, organization_slug: "contoso", allowed_project_ids: [ @project_id ])
      stub_tenant
      stub_azure_token(tenant_id: @tenant)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ { id: @project_id, name: "Customer Platform" },
                                    { id: SecureRandom.uuid, name: "Unapproved" } ] }.to_json)

      result = @onboarding.inspect!(organization: "contoso")

      assert result.already_bound
      # Still intersected with the approved scope — the binding does not widen
      # just because the application can see more.
      assert_equal [ @project_id ], result.projects.map { |p| p[:id] }
      assert_equal bound.id, @onboarding.complete!(organization: "contoso", project_ids: [ @project_id ]).id
    end

    test "approving a NEW project for a bound organization still needs a token" do
      create(:azure_devops_installation, :active, :approved, company: @company,
             tenant_id: @tenant, organization_slug: "contoso", allowed_project_ids: [ @project_id ])
      stub_tenant

      error = assert_raises(ValidationFailed) do
        @onboarding.complete!(organization: "contoso", project_ids: [ SecureRandom.uuid ])
      end
      assert_match(/personal access token is required/, error.message)
    end

    # The bind belongs to one company. Another company naming the same
    # organization gets no shortcut — it proves control itself or gets nothing.
    test "another company's binding does not let this company skip the proof" do
      create(:azure_devops_installation, :active, :approved, tenant_id: @tenant, organization_slug: "contoso")
      stub_tenant

      assert_raises(ValidationFailed) { @onboarding.inspect!(organization: "contoso") }
    end

    private

    # An app-only token is a JWT whose `oid` claim is the service principal's
    # object id in the issuing tenant. Only the payload segment is read.
    def token_with_oid(oid)
      payload = Base64.urlsafe_encode64({ oid: oid, tid: @tenant }.to_json, padding: false)
      "header.#{payload}.signature"
    end
  end
end
