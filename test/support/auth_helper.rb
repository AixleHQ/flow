module AuthHelper
  TEST_PASSWORD = "TestPassword1!"

  # Controller tests: write directly into the session.
  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session[:user_id] = nil
  end

  # Integration tests: POST to the login form so the session cookie is set.
  def sign_in_as(user, password: TEST_PASSWORD)
    post login_path, params: { user: { email: user.email, password: password } }
  end
end
