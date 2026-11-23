# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_client do
    issuer { "https://github.com/login/oauth" }
    sequence(:client_id) { |n| "Iv1.client#{n}" }
    authorization_endpoint { "https://github.com/login/oauth/authorize" }
    token_endpoint { "https://github.com/login/oauth/access_token" }
    source { "static" }
    scopes { "" }

    trait :gitlab do
      issuer { Gitlab::Host.web_base }
      authorization_endpoint { "#{Gitlab::Host.web_base}/oauth/authorize" }
      token_endpoint { "#{Gitlab::Host.web_base}/oauth/token" }
      scopes { "api" }
    end

    trait :bitbucket do
      issuer { Bitbucket::AppConfig::WEB_HOST }
      authorization_endpoint { "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/authorize" }
      token_endpoint { "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/access_token" }
      scopes { "" }
    end
  end
end
