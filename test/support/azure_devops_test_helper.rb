# frozen_string_literal: true

# Shared setup for the Azure DevOps adapter tests.
#
# Everything Azure-facing is off by a deployment switch, so a test that does not
# enable it exercises the disabled path — which is itself worth asserting, but is
# not what most of these tests are about. `with_azure_devops_enabled` supplies a
# complete operator configuration; the app credential is a client secret rather
# than a certificate because the certificate path has its own focused test.
module AzureDevopsTestHelper
  AZURE_TOKEN_HOST = "https://login.microsoftonline.com"
  AZURE_API_HOST = "https://dev.azure.com"

  def with_azure_devops_enabled(pat_mode: false, credential_generation: "v1")
    Settings.stubs(:azure_devops).returns(
      Hashie::Mash.new(
        enabled: true,
        pat_mode_enabled: pat_mode,
        resource: "https://app.vssps.visualstudio.com/.default",
        login_host: AZURE_TOKEN_HOST,
        api_host: AZURE_API_HOST,
        git_credentials_url: "http://web:4002/azure/git/credentials",
        token_refresh_skew: 300,
        open_timeout: 1,
        read_timeout: 2,
        apps: {
          "default" => {
            "client_id" => "11111111-1111-1111-1111-111111111111",
            "client_secret" => "operator-secret",
            "credential_generation" => credential_generation
          }
        }
      )
    )
  end

  # The Entra client-credentials exchange. Returns the stub so a test can assert
  # how many times it was hit — "the cache served the second call" is a claim
  # about request count, not about state.
  def stub_azure_token(tenant_id:, token: "azure-access-token", expires_in: 3600, status: 200, body: nil)
    stub_request(:post, "#{AZURE_TOKEN_HOST}/#{tenant_id}/oauth2/v2.0/token")
      .to_return(
        status: status,
        headers: { "Content-Type" => "application/json" },
        body: (body || { access_token: token, token_type: "Bearer", expires_in: expires_in }).to_json
      )
  end

  def azure_url(organization, *segments, **query)
    path = segments.map { |s| ERB::Util.url_encode(s.to_s) }.join("/")
    url = "#{AZURE_API_HOST}/#{ERB::Util.url_encode(organization)}/#{path}"
    query.present? ? "#{url}?#{query.to_query}" : url
  end
end
