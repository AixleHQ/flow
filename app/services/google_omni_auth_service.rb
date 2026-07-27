# frozen_string_literal: true

# Service to handle Google OAuth authentication (global identity) with a
# domain-based company auto-join policy for membershipless users
class GoogleOmniAuthService
  attr_reader :auth_hash, :user

  # Initialize with the OAuth auth hash from OmniAuth
  # @param auth_hash [OmniAuth::AuthHash] Auth hash from OmniAuth
  def initialize(auth_hash)
    @auth_hash = auth_hash
  end

  # Find or create a user based on the OAuth data
  # @return [User] The user found or created
  def authenticate
    @user = find_or_create_user
  end

  private

  # Find an existing user or create a new one. Identity lookup is GLOBAL
  # (email is globally unique); company access lives on memberships.
  # @return [User] The user found or created
  def find_or_create_user
    user = User.find_or_initialize_by(email: email)

    if user.new_record?
    end

    # Update OAuth-related identity attributes. We deliberately do NOT persist the
    # Google access/refresh tokens: they were dead plaintext columns (never read) and
    # have been dropped (oauth-unification §7). Google OAuth here is login-only.
    user.assign_attributes(
      name: name,
      avatar_url: image,
      provider: provider,
      uid: uid
    )

    user.save!
    ensure_domain_membership(user)
    user
  end

  # Email-domain match is an AUTO-JOIN policy, not a membership requirement:
  # it applies only to users with ZERO memberships (any state) — an existing or
  # pending invitation always wins over domain auto-join. `auto_accept_users`
  # decides whether the auto-joined membership is immediately active or awaits
  # admin approval (the former user.state = pending semantics, now per company).
  def ensure_domain_membership(user)
    return if user.super_admin?
    return if user.company_memberships.exists?

    company = Company.find_by_email_domain(email)
    return unless company

    if company.auto_accept_users
      user.company_memberships.create!(company: company, role: "employee", state: "active", accepted_at: Time.current)
    else
      user.company_memberships.create!(company: company, role: "employee", state: "invited")
    end
  end

  # Extract provider from auth hash
  # @return [String]
  def provider
    @provider ||= auth_hash.provider
  end

  # Extract uid from auth hash
  # @return [String]
  def uid
    @uid ||= auth_hash.uid
  end

  # Extract email from auth hash
  # @return [String]
  def email
    @email ||= auth_hash.info.email
  end

  # Extract name from auth hash
  # @return [String]
  def name
    @name ||= auth_hash.info.name
  end

  # Extract image from auth hash if present
  # @return [String, nil]
  def image
    @image ||= auth_hash.info.image if auth_hash.info.image.present?
  end
end
