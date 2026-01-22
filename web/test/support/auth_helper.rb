module AuthHelper
  # Signs in a user in test environment (for controller tests)
  def sign_in(user)
    session[:user_id] = user.id
  end

  # Signs out a user in test environment
  def sign_out
    session[:user_id] = nil
  end

  # Signs in a user for integration tests (sets session directly)
  def sign_in_as(user)
    post api_v1_sessions_path, params: { user: { email: user.email, password: user.password } }, as: :json
    # Session is set by the controller, no need to follow redirect
  end
end
