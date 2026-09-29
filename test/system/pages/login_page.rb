# frozen_string_literal: true

# SitePrism page object for the Inertia login screen (Auth/LoginPage).
#
# Signing in is two screens: an address, then whatever the workspace that domain
# resolves to actually accepts. The password box only exists on the second, so
# #sign_in walks both.
class LoginPage < SitePrism::Page
  set_url "/login"

  element :email_field, :fillable_field, "Email"
  element :continue_button, :button, "Continue"
  element :password_field, :fillable_field, "Password"
  element :submit_button, :button, "Sign in"
  element :error_alert, ".mantine-Alert-root"

  def sign_in(email, password)
    identify(email)
    password_field.set(password)
    submit_button.click
  end

  # Step one on its own, for a test that cares what the second step offers.
  def identify(email)
    email_field.set(email)
    continue_button.click
    # The second step is a fresh render from the server; without waiting for it
    # the password box is still the one that does not exist yet.
    has_password_field?(wait: 10)
  end
end
