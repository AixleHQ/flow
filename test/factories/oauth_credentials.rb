# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_credential do
    owner factory: :user
    oauth_client
    provider { "sentry" }
    status { :active }
    expires_at { 8.hours.from_now }

    after(:build) do |credential|
      credential.access_token ||= "at-#{SecureRandom.hex(6)}"
      credential.refresh_token ||= "rt-#{SecureRandom.hex(6)}"
    end

    # A user's own GitHub connection (docs/design/github-user-identity.md §3.3).
    trait :github_user do
      provider { "github" }
      oauth_client factory: %i[oauth_client github_current]
      metadata { { "github_user" => { "id" => 123, "login" => "octo-user", "name" => "Octo User",
                                        "avatar_url" => "https://a.test/123", "fetched_at" => Time.current.iso8601 } } }
    end

    # A user's own GitLab connection (docs/design/gitlab-user-identity.md §3), made against
    # the instance this deployment points at.
    trait :gitlab_user do
      provider { "gitlab" }
      oauth_client factory: %i[oauth_client gitlab]
      expires_at { 2.hours.from_now }
      metadata { { "gitlab_user" => { "id" => 456, "username" => "lab-user", "name" => "Lab User",
                                        "avatar_url" => "https://a.test/456", "commit_email" => "456-lab-user@users.noreply.gitlab.com",
                                        "fetched_at" => Time.current.iso8601 } } }
    end

    # A user's own Bitbucket connection (docs/design/bitbucket-user-identity.md §3).
    trait :bitbucket_user do
      provider { "bitbucket" }
      oauth_client factory: %i[oauth_client bitbucket]
      expires_at { 2.hours.from_now }
      metadata { { "bitbucket_user" => { "id" => "{6c1f0a4e-0000-4000-8000-0000000000b1}", "nickname" => "bb-user",
                                           "name" => "Bee Bucket", "avatar_url" => "https://a.test/bb",
                                           "commit_email" => "bee@example.com", "fetched_at" => Time.current.iso8601 } } }
    end
  end
end
