# frozen_string_literal: true

# Jira Cloud in tests: `with_jira_oauth_app` configures the deployment's OAuth
# app, `stub_jira!` hands every Jira::Api the one FakeJira::Api it returns.
# Jira::Client, Credential and Oauth stay real and are contract-tested against
# WebMock in test/services/jira/.
module JiraTestHelper
  JIRA_API = "https://api.atlassian.com"
  JIRA_AUTH = "https://auth.atlassian.com"

  def with_jira_oauth_app(client_id: "jira-app-client", client_secret: "jira-app-secret", webhook_base_url: "https://flow.example.com")
    Settings.stubs(:jira).returns(Hashie::Mash.new(client_id: client_id, client_secret: client_secret,
                                                   webhook_base_url: webhook_base_url))
  end

  def stub_jira!
    fake = FakeJira::Api.new
    Jira::Api.stubs(:new).returns(fake)
    fake
  end

  def jira_url(cloud_id, *segments)
    "#{JIRA_API}/ex/jira/#{cloud_id}/rest/#{segments.join('/')}"
  end
end
