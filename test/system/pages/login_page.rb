# frozen_string_literal: true

# SitePrism page object for the Inertia login screen (Auth/LoginPage).
class LoginPage < SitePrism::Page
  set_url "/login"

  element :email_field, :fillable_field, "Email"
  element :password_field, :fillable_field, "Password"
  element :submit_button, :button, "Sign in"
  element :error_alert, ".mantine-Alert-root"

  def sign_in(email, password)
    email_field.set(email)
    password_field.set(password)
    submit_button.click
  end
end
