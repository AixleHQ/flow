# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_client do
    issuer { "https://github.com" }
    sequence(:client_id) { |n| "Iv1.client#{n}" }
    authorization_endpoint { "https://github.com/login/oauth/authorize" }
    token_endpoint { "https://github.com/login/oauth/access_token" }
    source { "static" }
    scopes { "" }
  end
end
