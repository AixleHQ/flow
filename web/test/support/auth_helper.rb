module AuthHelper
  # Signs in a user in test environment
  def sign_in(user)
    session[:user_id] = user.id
  end

  # Signs out a user in test environment
  def sign_out
    session[:user_id] = nil
  end
end
