# frozen_string_literal: true

# Shared setup for the Azure DevOps adapter tests.
#
# The feature is offered exactly when an operator has configured something that
# can reach Azure, so "enabled" in these tests means "a usable app
# configuration exists" rather than a flag being set. `with_azure_devops_enabled`
# supplies a complete one; the app credential is a client secret rather than a
# certificate because the certificate path has its own focused test.
# `with_azure_devops_unconfigured` is the other side — a deployment where nobody
# has set the feature up.
module AzureDevopsTestHelper
  AZURE_TOKEN_HOST = "https://login.microsoftonline.com"
  AZURE_API_HOST = "https://dev.azure.com"

  def with_azure_devops_enabled(pat_mode: false, credential_generation: "v1")
    Settings.stubs(:azure_devops).returns(
      Hashie::Mash.new(
        pat_mode_enabled: pat_mode,
        resource: "https://app.vssps.visualstudio.com/.default",
        login_host: AZURE_TOKEN_HOST,
        api_host: AZURE_API_HOST,
        git_credentials_url: "http://web:4002/azure/git/credentials",
        token_refresh_skew: 300,
        # Zero, so the completion-confirmation loop does not spend real seconds
        # in the suite. The interval is configuration precisely so no test has to
        # stub sleep (docs/testing.md R7).
        completion_poll_interval: 0,
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

  # No client id and no credential: nothing an operator did makes Azure
  # reachable, so the feature is not offered at all.
  def with_azure_devops_unconfigured
    Settings.stubs(:azure_devops).returns(
      Hashie::Mash.new(pat_mode_enabled: false, apps: { "default" => { "client_id" => nil } })
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
