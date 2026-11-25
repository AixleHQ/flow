# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_client do
    issuer { "https://github.com/login/oauth" }
    sequence(:client_id) { |n| "Iv1.client#{n}" }
    authorization_endpoint { "https://github.com/login/oauth/authorize" }
    token_endpoint { "https://github.com/login/oauth/access_token" }
    source { "static" }
    scopes { "" }

    # (issuer, client_id) is unique: the clients of a deployment's own connections are shared.
    initialize_with { OauthClient.find_or_initialize_by(issuer: issuer, client_id: client_id) }

    # The client the deployment is configured with: the client id its settings name, or
    # the one the tests usually stub when none is set. A person's own connection counts
    # only when made with it (OauthCredential.on_other_client).
    trait :github_current do
      client_id { Oauth::Providers.current_client_ref("github")&.fetch(:client_id) || "Iv1.client" }
    end

    trait :gitlab do
      issuer { Gitlab::Host.web_base }
      authorization_endpoint { "#{Gitlab::Host.web_base}/oauth/authorize" }
      token_endpoint { "#{Gitlab::Host.web_base}/oauth/token" }
      scopes { "api" }
      client_id { Oauth::Providers.current_client_ref("gitlab")&.fetch(:client_id) || "lab-cid" }
    end

    trait :bitbucket do
      issuer { Bitbucket::AppConfig::WEB_HOST }
      authorization_endpoint { "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/authorize" }
      token_endpoint { "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/access_token" }
      scopes { "" }
      client_id { Oauth::Providers.current_client_ref("bitbucket")&.fetch(:client_id) || "bb-cid" }
    end
  end
end
