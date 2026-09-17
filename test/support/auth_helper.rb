# frozen_string_literal: true

module AuthHelper
  TEST_PASSWORD = "TestPassword1!"

  # Controller tests: write directly into the session. Authentication now needs
  # a live UserSession as well as the effective user id (AD-6), so the helper
  # mints one and proves the password provider by default.
  def sign_in(user, provider: IdentityProvider.password)
    started = Auth::SessionService.start(user: user, provider: provider)
    session[:user_id] = user.id
    session[AuthConcern::AUTH_SESSION_KEY] = started.token
    started.user_session
  end

  def sign_out
    session[:user_id] = nil
    session.delete(:user_session_id)
  end

  # Integration tests: POST to the login form so the session cookie is set.
  def sign_in_as(user, password: TEST_PASSWORD)
    post login_path, params: { user: { email: user.email, password: password } }
  end
end
