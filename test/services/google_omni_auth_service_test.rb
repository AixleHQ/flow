# frozen_string_literal: true

require "test_helper"

class GoogleOmniAuthServiceTest < ActiveSupport::TestCase
  # Build a realistic OmniAuth auth hash (same shape the sessions controller
  # passes in from `request.env["omniauth.auth"]`).
  def build_auth_hash(email:, uid:, name: "Jane Doe", provider: "google_oauth2",
                      token: "ya29.access-token", refresh_token: "1//refresh-token",
                      image: "https://lh3.googleusercontent.com/a/avatar.png")
    info = { email: email, name: name }
    info[:image] = image unless image.nil?

    credentials = { token: token }
    credentials[:refresh_token] = refresh_token unless refresh_token.nil?

    OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: info,
      credentials: credentials
    )
  end

  test "creates an active user when the matching company auto-accepts" do
    company = create(:company, :auto_accept)
    email = "new.hire@#{company.email_domain}"
    auth_hash = build_auth_hash(email: email, uid: "google-uid-active")

    user = nil
    assert_difference("User.count", 1) do
      user = GoogleOmniAuthService.new(auth_hash).authenticate
    end

    assert user.persisted?, user.errors.full_messages.to_sentence
    assert_equal company, user.company
    assert_equal "active", user.state
    assert_equal "employee", user.role
    assert_equal "en", user.preferred_agent_language
    assert_nil user.position

    # OAuth attributes persisted from the auth hash.
    assert_equal email, user.email
    assert_equal "Jane Doe", user.name
    assert_equal "google_oauth2", user.provider
    assert_equal "google-uid-active", user.uid
    assert_equal "ya29.access-token", user.google_token
    assert_equal "1//refresh-token", user.google_refresh_token
    assert_equal "https://lh3.googleusercontent.com/a/avatar.png", user.avatar_url
  end

  test "creates a pending user when the matching company does not auto-accept" do
    company = create(:company) # auto_accept_users defaults to false
    email = "pending.hire@#{company.email_domain}"
    auth_hash = build_auth_hash(email: email, uid: "google-uid-pending")

    user = nil
    assert_difference("User.count", 1) do
      user = GoogleOmniAuthService.new(auth_hash).authenticate
    end

    assert user.persisted?, user.errors.full_messages.to_sentence
    assert_equal company, user.company
    assert_equal "pending", user.state
    assert_equal "employee", user.role
  end

  test "persists nil refresh token and avatar when the auth hash omits them" do
    company = create(:company, :auto_accept)
    email = "minimal@#{company.email_domain}"
    auth_hash = build_auth_hash(
      email: email,
      uid: "google-uid-minimal",
      refresh_token: nil,
      image: nil
    )

    user = GoogleOmniAuthService.new(auth_hash).authenticate

    assert user.persisted?, user.errors.full_messages.to_sentence
    assert_equal "ya29.access-token", user.google_token
    assert_nil user.google_refresh_token
    assert_nil user.avatar_url
  end

  test "refreshes tokens for an existing user without changing state, role or company" do
    company = create(:company)
    existing = create(:user, :admin, :pending, company: company)
    original_state = existing.state
    auth_hash = build_auth_hash(
      email: existing.email,
      uid: "google-uid-returning",
      name: "Renamed User",
      token: "ya29.rotated-token",
      refresh_token: "1//rotated-refresh",
      image: "https://lh3.googleusercontent.com/a/new-avatar.png"
    )

    user = nil
    assert_no_difference("User.count") do
      user = GoogleOmniAuthService.new(auth_hash).authenticate
    end

    assert_equal existing.id, user.id

    # OAuth attributes were refreshed.
    assert_equal "Renamed User", user.name
    assert_equal "ya29.rotated-token", user.google_token
    assert_equal "1//rotated-refresh", user.google_refresh_token
    assert_equal "https://lh3.googleusercontent.com/a/new-avatar.png", user.avatar_url
    assert_equal "google_oauth2", user.provider
    assert_equal "google-uid-returning", user.uid

    # Pre-existing account attributes were preserved (only new users get these set).
    assert_equal company, user.company
    assert_equal "admin", user.role
    assert_equal original_state, user.state

    # Changes are persisted, not just in-memory.
    assert_equal "ya29.rotated-token", user.reload.google_token
  end
end
