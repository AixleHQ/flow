# frozen_string_literal: true

# The profile's "Connected accounts" card: a user's own connected account at a
# provider (docs/design/github-user-identity.md §4.2). Never carries a token.
class UserConnectionResource < ApplicationResource
  typelize_from OauthCredential

  attributes :provider

  typelize "'connected' | 'needs_reconnect'"
  attribute :status do |credential|
    credential.active? && credential.tokens_readable? ? "connected" : "needs_reconnect"
  end

  typelize "string | null"
  attribute :login do |credential|
    identity = UserConnectionResource.identity_of(credential)
    identity["login"] || identity["username"]
  end

  typelize "string | null"
  attribute :name do |credential|
    UserConnectionResource.identity_of(credential)["name"]
  end

  typelize "string | null"
  attribute :avatar_url do |credential|
    UserConnectionResource.identity_of(credential)["avatar_url"]
  end

  typelize "string"
  attribute :connected_at do |credential|
    credential.created_at.iso8601
  end

  # The account's identity as the provider reported it, whichever provider this is.
  def self.identity_of(credential)
    metadata = credential.metadata.to_h
    metadata["github_user"] || metadata["gitlab_user"] || {}
  end
end
