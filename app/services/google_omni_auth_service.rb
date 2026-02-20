# frozen_string_literal: true

# Service to handle Google OAuth authentication with company assignment
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

  # Find an existing user or create a new one with company assignment
  # @return [User] The user found or created
  def find_or_create_user
    user = User.find_or_initialize_by(email: email)

    # Find company by email domain if user is new
    if user.new_record?
      company = Company.find_by_email_domain(email)

      user.company = company
      user.state = company&.auto_accept_users ? "active" : "pending"
      user.role = "employee" # Default role for OAuth users
      user.position = nil
      user.preferred_agent_language = "en"
    end

    # Update OAuth-related attributes (always update tokens)
    user.assign_attributes(
      name: name,
      google_token: token,
      google_refresh_token: refresh_token,
      avatar_url: image,
      provider: provider,
      uid: uid
    )

    user.save!
    user
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

  # Extract token from auth hash
  # @return [String]
  def token
    @token ||= auth_hash.credentials.token
  end

  # Extract refresh token from auth hash if present
  # @return [String, nil]
  def refresh_token
    @refresh_token ||= auth_hash.credentials.refresh_token if auth_hash.credentials.refresh_token.present?
  end

  # Extract image from auth hash if present
  # @return [String, nil]
  def image
    @image ||= auth_hash.info.image if auth_hash.info.image.present?
  end
end
